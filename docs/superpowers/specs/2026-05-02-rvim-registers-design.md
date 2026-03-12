# Rvim v1.5: Registers — Design Spec

## Context

Today every yank, delete, and change writes to a single `@rvim_clipboard`. There's no way to keep two pieces of text around or pull from the system clipboard. Vim's solution is **registers** — a namespace of named text slots that operators read from and write to. This plan adds:

- **Named registers** `"a`–`"z` for explicit per-name storage, with `"A`–`"Z` to *append*
- **Numbered registers** `"0` (last yank), `"1`–`"9` (deletion ring, most recent at `"1`)
- **Unnamed register** `""` — what every yank/delete writes to and what `p` reads from by default. Equals current `@rvim_clipboard`
- **System clipboard `"+`** — wrapped around `pbcopy` / `pbpaste` on macOS, `xclip -selection clipboard` on Linux
- **Read-only `"%`** — current filename (small, useful, free)

Out of scope (deferred):

- Macro/text register unification. v1.4 macros live in `@macros`; this plan keeps that table separate. A future plan can serialize macro keys to text and unify
- `"*` X11 primary selection
- `"_` blackhole (register that nothing reads from / writes to)
- `"#` alternate filename (we don't track alternate buffers yet)
- `"/`, `":`, `"=`, `".` (last search, last command, expression, last inserted)
- `:registers` listing UI

## Architecture

### Single source of truth

Replace `@rvim_clipboard` (single string + kind tag) with `@registers`, a `Hash<String, RegisterEntry>` where:

```ruby
RegisterEntry = Struct.new(:text, :kind) # text: String or Array<String>, kind: :char/:line/:block
```

Keys are single-char register names (`'a'..'z'`, `'0'..'9'`, `'"'`, `'+'`, `'%'`).

The unnamed register `""` becomes the default for reads (`p`) and writes (`y`/`d`/`c`). Any operation that names a register routes to that register *and* duplicates into `""` (matches vim).

### `"<reg>` prefix dispatch

A new `@pending_register` slot. Set when the user types `"` in normal or visual mode followed by a single char:

```
"a y w   →   yank inner word into register a (and unnamed)
"a p     →   paste from register a
"A y w   →   append-yank inner word to register a
"+ y y   →   yank current line into system clipboard
```

In `update(key)`, if `@pending_register` is nil and `key.char == '"'`, arm `@waiting_proc` to consume the next char as the register name. After consuming, leave `@pending_register` set so the next operator picks it up.

After the operator (or after one keystroke if it's a no-op like a motion), clear `@pending_register`.

### Where the operators read/write

`Operations.yank(editor, sel)` currently calls `editor.set_clipboard(text, kind)`. Change it to:

```ruby
def self.yank(editor, sel)
  text, kind = capture(editor, sel)
  editor.write_register(text, kind, register: editor.pending_register)
  editor.consume_pending_register
end
```

`editor.write_register(text, kind, register:)`:

- Default to `""` (unnamed) when `register` is nil.
- Write to the named register.
- *Always* also copy into `""`.
- For numbered registers on yank: also write to `"0`.
- For numbered registers on delete: shift `"1`→`"2`, ..., write to `"1`.
- For uppercase names (`"A`–`"Z`): *append* to the lowercase counterpart instead of overwriting.

`editor.read_register(register:)` returns the `RegisterEntry`. Defaults to `""`. For `"%`, return `RegisterEntry.new(@filepath || '', :char)`. For `"+`, shell out to `pbpaste`/`xclip` (cached on demand to avoid a process spawn per render).

### System clipboard `"+`

`pbpaste`/`pbcopy` on macOS, `xclip -selection clipboard -o`/`-i` on Linux. Detect once at startup; fall back to a no-op (with status message on attempted use) if neither is available.

```ruby
SystemClipboard.read   # -> String
SystemClipboard.write(text)  # -> bool
```

Single-line content stays single-line; multi-line content writes/reads with newlines preserved. Kind tagging: vim treats `"+` as charwise unless it ends with `\n` (then linewise). Mirror that.

### File layout (additive)

```
lib/rvim/
  register.rb          # NEW — RegisterEntry struct, register table operations
                       # (write, read, append, numbered-shift)
  system_clipboard.rb  # NEW — pbcopy/xclip wrapper
  editor.rb            # @registers / @pending_register / "<reg> dispatch;
                       # remove @rvim_clipboard, @rvim_clipboard_kind
  operations.rb        # yank/delete/change use editor.write_register;
                       # paste reads from named or unnamed register
test/
  test_register.rb     # NEW — write/read/append/numbered-shift
  test_editor.rb       # add "a y w + "a p PTY-style tests
```

## Components

### 1. `Rvim::Register` (or just inline on Editor)

```ruby
module Rvim
  RegisterEntry = Struct.new(:text, :kind)

  class Registers
    def initialize
      @table = {}
    end

    def write(name, text, kind, append: false)
      effective = name.downcase
      append ||= name != name.downcase  # uppercase → append

      if append && @table.key?(effective)
        existing = @table[effective]
        new_text = if existing.kind == :line || kind == :line
                     existing.text.to_s + (existing.text.to_s.end_with?("\n") ? '' : "\n") + text.to_s
                   else
                     existing.text.to_s + text.to_s
                   end
        @table[effective] = RegisterEntry.new(new_text, kind)
      else
        @table[effective] = RegisterEntry.new(text, kind)
      end

      # Always mirror to the unnamed register
      @table['"'] = @table[effective].dup unless effective == '"'
    end

    def write_unnamed(text, kind)
      @table['"'] = RegisterEntry.new(text, kind)
    end

    def write_yank_history(text, kind)
      @table['0'] = RegisterEntry.new(text, kind)
    end

    def write_delete_history(text, kind)
      ('1'..'8').each do |i|
        @table[(i.to_i + 1).to_s] = @table[i] if @table.key?(i)
      end
      @table['1'] = RegisterEntry.new(text, kind)
    end

    def read(name)
      @table[name]
    end
  end
end
```

Editor wires `@registers = Registers.new` and exposes `read_register` / `write_register` helpers.

### 2. Prefix dispatch (`"`)

Bind `"` (0x22) in vi_command and visual to `:rvim_register_prefix`:

```ruby
private def rvim_register_prefix(key)
  @waiting_proc = lambda do |reg_key, _sym|
    @waiting_proc = nil
    ch = reg_key.is_a?(Integer) ? reg_key.chr : reg_key.to_s
    @pending_register = ch if valid_register_name?(ch)
  end
end

private def valid_register_name?(ch)
  ch =~ /\A[a-zA-Z0-9"+%]\z/
end
```

`@pending_register` is consumed by the *next* operator (y/d/c/p/P) and then cleared. If the next keystroke is something else (a motion, Esc), clear silently.

To make this work, `Operations.yank/delete/change` and the paste paths read `editor.pending_register`, then call `editor.consume_pending_register` to clear it.

### 3. Operator wiring

Each operator path passes the register through:

- v1.4 `vi_delete_meta_confirm` (charwise): captures into `@pending_register`, also writes `"1` (numbered shift), unnamed.
- v1.4 `delete_lines_linewise` (dd/cc/yy): same, but the linewise variants.
- v1.4 `Operations.yank` from visual: routes through `editor.write_register`.
- v1.4 `Operations.delete` / `change`: routes likewise.
- v1.4 `vi_yank_confirm`: writes to register + `"0`.

The paste paths (`rvim_paste_after`/`rvim_paste_before`) read `editor.read_register(@pending_register || '"')` and dispatch by `kind`.

### 4. Numbered register lifecycle

- `"0` updated on every yank only (vim semantics).
- `"1`–`"9` shifted on every delete (where the delete actually removed text — a no-op delete shouldn't pollute the ring).
- Linewise + charwise + blockwise all go through the same shift.

### 5. System clipboard `"+`

```ruby
module Rvim::SystemClipboard
  def self.available?
    @available ||= detect_tool != nil
  end

  def self.read
    case detect_tool
    when :pbpaste then `pbpaste`
    when :xclip   then `xclip -selection clipboard -o`
    end
  end

  def self.write(text)
    case detect_tool
    when :pbpaste then IO.popen('pbcopy', 'w') { |io| io.write(text) }
    when :xclip   then IO.popen('xclip -selection clipboard -i', 'w') { |io| io.write(text) }
    end
  end

  def self.detect_tool
    @tool ||= if RUBY_PLATFORM =~ /darwin/ && which('pbpaste') then :pbpaste
              elsif which('xclip') then :xclip
              end
  end

  def self.which(cmd)
    ENV['PATH'].split(File::PATH_SEPARATOR).find { |d| File.executable?(File.join(d, cmd)) }
  end
end
```

In `Editor#read_register('+')` / `write_register(text, kind, register: '+')`, route to `SystemClipboard.read` / `write`. Cache the read on first access per session — re-read only on demand. Or simpler: read every time. `pbpaste` is fast.

### 6. Read-only `"%`

`Editor#read_register('%')` returns the current `@filepath` as a charwise text register. Writes to `"%` are silent no-ops (with maybe a status message).

## Key Technical Decisions

### Replacing `@rvim_clipboard`

The unnamed register `""` *is* the v1.4 clipboard. Migration strategy:

- Add `@registers` and migrate writers (visual yank, dd/cc/yy, vi_*_confirm) to `editor.write_register`.
- Replace `editor.set_clipboard` with `editor.write_register(text, kind)` defaulting to `""`.
- Replace reads in paste paths to call `editor.read_register('"')`.

There's no semantic change for users who never specify a register — defaults preserve v1.4 behavior.

### Why mirror to unnamed on every named-register write?

Vim does this. Concretely: `"ay y` then `p` (without specifying `"a`) pastes the same text. Mirroring to `""` on every write keeps the unnamed register tracking the most recent operation regardless of which named register was used.

### When does `@pending_register` clear?

Vim's rule: after a single operator. Implementing that strictly means we need to detect "an operator just ran." Approximation: clear `@pending_register` at the end of every `update(key)` *unless* the key was the prefix `"` or its register-name follow-up. Simpler still: clear inside the operator implementations themselves (where we already call `consume_pending_register`).

We may miss edge cases (e.g., `"a` followed by an unrelated motion shouldn't carry the `"a` over to a later operator). Add a watchdog: clear `@pending_register` after any non-operator keystroke completes.

### Macro register namespace

v1.4's `@macros` hash uses single-char names `a`–`z`. After this plan, `"a` for clipboard and `qa`/`@a` for macros use *the same letters but different storage*. This diverges from vim.

Documented divergence. Acceptable because:

- Most users don't conflate them mentally
- A unified register would require key-sequence ↔ text serialization (non-trivial; lossy for special keys)
- The file we'd need is a future plan

Status messages should reference the right one when the user trips over it (e.g., recording into `qa` doesn't show up in `:registers` listing; defer that listing).

## Verification Plan

### Unit tests (`test/test_register.rb`)

- `write` and `read` round-trip per name.
- `write` mirrors to `""`.
- `write` with uppercase name appends.
- `write_yank_history` updates `"0`.
- `write_delete_history` shifts `"1`–`"8` and writes new `"1`.
- Linewise + charwise round-trip with kind preserved.

### PTY end-to-end

1. `"ay y` then `"ap` round-trips a line.
2. `"ay y` then plain `p` (uses unnamed mirror) — same result.
3. `"Ay y` after `"ay y` appends.
4. `dd dd` then `"1p` and `"2p` recovers the deletion ring (most recent at `"1`).
5. `yy` then `"0p` pastes last yank from `"0`.
6. `"+y y` writes to system clipboard; verify with `pbpaste`.
7. `"+p` pulls from system clipboard.
8. `"%p` pastes the current filename.
9. `"a` followed by a motion (no operator) — pending register cleared cleanly, next operator unaffected.
10. After `"ay y`, user types `dd` (no register prefix) — `"a` retains the yank, the dd updates `"1`/`""`.

## Stages

1. **Register table foundation** — `Rvim::Registers` class with write/read/append/yank-history/delete-history. Unit tests.
2. **Migration** — replace `@rvim_clipboard` / `@rvim_clipboard_kind` everywhere with `@registers` writes/reads to `""` (no behavior change). Verify v1+ regression suite still passes.
3. **`"<reg>` prefix dispatch** — `@pending_register`, `rvim_register_prefix`, `consume_pending_register`. Bind `"` in vi_command + visual.
4. **Named register read/write** — `"ay`, `"ap`, `"Ay` (append). Operator and paste paths consult `@pending_register`.
5. **Numbered registers** — `"0` on yank, `"1`–`"9` ring-shift on delete.
6. **System clipboard `"+`** — `Rvim::SystemClipboard` wrapper; route reads/writes for `"+` register name through it.
7. **Filename register `"%`** — read-only access to `@filepath`.
8. **PTY end-to-end** — run the 10 verification scenarios; iterate.

Stretch:

- `:registers` listing command (multiline status display).
- `"_` blackhole.
- `"/` last-search exposure.
