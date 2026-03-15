# Rvim v1.6: Marks + Jump List — Design Spec

## Context

Marks are vim's named bookmarks. After dropping a mark with `m{a-z}`, the user can return to that line/column from anywhere with `'a` or `` `a ``. The jump list is the chronological history of "interesting" cursor moves — `Ctrl-O` walks back, `Ctrl-I` walks forward.

Both are core navigation that pair naturally with v1.5's named registers (same single-letter namespace shape, similar `m`/`"` prefix dispatch).

This plan covers:

- `m{a-z}` set a buffer-local mark
- `'<reg>` jump to mark's line (cursor at first non-whitespace, like vim)
- `` `<reg> `` jump to mark's exact line+column
- Special `'` `` ` `` registers: `'<` / `'>` (last visual selection start/end), `''` / `` `` `` (position before the last jump)
- Jump list: `Ctrl-O` previous position, `Ctrl-I` forward
- Jump-list pushes on: `/` `?` Enter, `n`/`N`, `*`/`#`, `G`, `gg`, `:N`, mark jumps

Out of scope (deferred):

- Global marks `m{A-Z}` (need multi-buffer infrastructure first)
- `'.` last change, `'^` last insert, `'[` / `']` yank/change range
- `:marks` and `:jumps` listing commands
- Marks persistence across sessions (`viminfo`)

## Architecture

### Mark storage

```ruby
@marks  # Hash<String, [line_index, byte_pointer]>
```

Single-buffer scope. Cleared on `:e <new file>` (since the line numbers no longer match anything meaningful). Special read-only marks computed on read:

- `'<` / `'>` → `@last_visual[:anchor]` / `@last_visual[:last_end]`
- `''` / `` `` `` → `@jump_list[@jump_index - 1]` (pre-jump position)

### `m`, `'`, `` ` `` prefix dispatch

Three new bindings in `vi_command`:

- `m` (109) → `:rvim_mark_prefix` — arms `@waiting_proc` to consume next char as the mark name; stores `[@line_index, @byte_pointer]`.
- `'` (39) → `:rvim_mark_jump_line` — arms `@waiting_proc`; on next char, look up the mark, set `@line_index` to the mark's line, `@byte_pointer` to the first non-whitespace col on that line.
- `` ` `` (96) → `:rvim_mark_jump_exact` — same dispatch, but jumps to exact `[line, col]`.

Validity: `[a-z]` for user marks; `'<`/`'>`/`''`/`` `` `` for special. Anything else: silent no-op.

### Jump list

```ruby
@jump_list   # Array<[line, col]>, oldest first
@jump_index  # Integer, points to the *current* position in @jump_list (or @jump_list.size if at "tip")
```

`push_jump(line, col)`:
- If we're not at the tip (`@jump_index < @jump_list.size`), drop everything after `@jump_index` (vim discards forward history when a new jump happens — same as undo).
- Append `[line, col]`.
- Cap the list at 100 entries (vim does 100 too).
- Set `@jump_index = @jump_list.size`.

`Ctrl-O` (`:rvim_jump_back`):
- If `@jump_index == @jump_list.size`, push the *current* position so we can return.
- Decrement `@jump_index`. Move cursor to `@jump_list[@jump_index]`.

`Ctrl-I` (Tab — `:rvim_jump_forward`):
- If `@jump_index < @jump_list.size - 1`, increment and move.

Pushes happen at:

- After `commit_search` (`/`/`?` Enter) — push *destination* position.
- After `n`/`N` — push destination.
- After `*`/`#` — push destination.
- After `G`/`gg`/`:N` — push destination.
- After mark jumps — push *both* origin and destination (like vim does).

### File layout (additive)

```
lib/rvim/
  marks.rb         # NEW — Marks class storing/recalling buffer marks
  editor.rb        # @marks / @jump_list / @jump_index;
                   # bind m/'/`/Ctrl-O/Ctrl-I; push_jump in motion sites
test/
  test_marks.rb    # NEW — set/get/special marks
  test_editor.rb   # add jump_list push tests
```

Marks logic is small enough to inline on Editor, but a separate class isolates the special-mark handling and keeps Editor lean. Decide during Stage 1.

## Components

### 1. `Rvim::Marks` (or inline)

```ruby
class Rvim::Marks
  def initialize
    @table = {}
  end

  def set(name, line, col)
    @table[name] = [line, col]
  end

  def clear
    @table.clear
  end

  def get(name, editor)
    case name
    when "'", '`'
      # Last jump position
      previous_jump_position(editor)
    when '<', '>'
      visual_position(name, editor)
    when /\A[a-z]\z/
      @table[name]
    end
  end

  private

  def previous_jump_position(editor)
    jl = editor.instance_variable_get(:@jump_list)
    idx = editor.instance_variable_get(:@jump_index)
    return nil if idx.nil? || idx <= 0

    jl[idx - 1]
  end

  def visual_position(which, editor)
    last = editor.instance_variable_get(:@last_visual)
    return nil unless last

    which == '<' ? last[:anchor] : last[:last_end]
  end
end
```

### 2. Mark dispatch on Editor

```ruby
private def rvim_mark_prefix(key)
  @waiting_proc = lambda do |reg_key, _sym|
    @waiting_proc = nil
    ch = reg_key.is_a?(Integer) ? reg_key.chr : reg_key.to_s
    if ch =~ /\A[a-z]\z/
      @marks.set(ch, @line_index, @byte_pointer)
    end
  end
end

private def rvim_mark_jump_line(key)
  @waiting_proc = lambda do |reg_key, _sym|
    @waiting_proc = nil
    pos = @marks.get(charify(reg_key), self)
    jump_to_mark(pos, line_only: true) if pos
  end
end

private def rvim_mark_jump_exact(key)
  @waiting_proc = lambda do |reg_key, _sym|
    @waiting_proc = nil
    pos = @marks.get(charify(reg_key), self)
    jump_to_mark(pos, line_only: false) if pos
  end
end

private def jump_to_mark(pos, line_only:)
  push_jump(@line_index, @byte_pointer)
  line, col = pos
  if line_only
    line_text = @buffer_of_lines[line] || ''
    col = line_text.bytes.find_index { |b| b != 0x20 && b != 0x09 } || 0
  end
  move_cursor_to(line, col)
  push_jump(@line_index, @byte_pointer)
end
```

### 3. Jump-list dispatch

```ruby
private def rvim_jump_back(key, arg: 1)
  arg.times do
    if @jump_index == @jump_list.size
      @jump_list << [@line_index, @byte_pointer]
    end
    break if @jump_index <= 0

    @jump_index -= 1
    line, col = @jump_list[@jump_index]
    move_cursor_to(line, col)
  end
end

private def rvim_jump_forward(key, arg: 1)
  arg.times do
    break if @jump_index >= @jump_list.size - 1

    @jump_index += 1
    line, col = @jump_list[@jump_index]
    move_cursor_to(line, col)
  end
end

def push_jump(line, col)
  return if @suspend_jump_record

  @jump_list = @jump_list.first(@jump_index) if @jump_index < @jump_list.size
  @jump_list << [line, col]
  @jump_list.shift if @jump_list.size > 100
  @jump_index = @jump_list.size
end
```

`@suspend_jump_record` lets the existing motion paths (`commit_search`, `vi_to_history_line`, etc.) call `push_jump` without recursing if we ever wire up "the act of pushing a jump triggered a render that re-pushed".

### 4. Wire push_jump into existing jumps

In `editor.rb`, add `push_jump` after the cursor moves in:

- `commit_search` (after the move)
- `rvim_search_next` / `rvim_search_prev` (after move)
- `search_word_under_cursor` (after move)
- `vi_to_history_line` (G — after move)
- `rvim_g_prefix`'s `gg` branch (after move to line 0)
- `Command.execute_substitute` — no, substitute doesn't move cursor
- `Command.execute :goto` (`:N`) — yes, after move

### 5. Bindings

In `install_key_bindings`:

```ruby
@config.add_default_key_binding_by_keymap(:vi_command, [?m.ord], :rvim_mark_prefix)
@config.add_default_key_binding_by_keymap(:vi_command, [?'.ord], :rvim_mark_jump_line)
@config.add_default_key_binding_by_keymap(:vi_command, [?`.ord], :rvim_mark_jump_exact)
@config.add_default_key_binding_by_keymap(:vi_command, [0x0F], :rvim_jump_back)    # Ctrl-O
@config.add_default_key_binding_by_keymap(:vi_command, [0x09], :rvim_jump_forward) # Ctrl-I (Tab)
```

Caveat: `Ctrl-I` is the same byte as Tab. In normal mode this is fine; in insert mode it stays a literal Tab (vim does the same).

## Key Technical Decisions

### Single-buffer scope

Local marks are per-buffer in vim. We're single-buffer for now, so `@marks` is just one Hash. When multi-buffer support arrives, this becomes a per-buffer attribute and global marks `m{A-Z}` get a separate top-level hash.

On `:e <new file>`, clear `@marks` (otherwise mark `'a` on line 5 of `foo.rb` could accidentally point at some random line in `bar.rb`).

### Jump-list "tip" semantics

When at the tip (`@jump_index == @jump_list.size`), `Ctrl-O` first records the current position so a subsequent `Ctrl-I` returns to where you were. After moving back through history, `Ctrl-I` walks forward again. Vim's exact semantics; lifted as-is.

### Why both `'a` and `` `a ``?

Vim's `'a` jumps to the first non-whitespace col of the mark's line; `` `a `` jumps to the exact saved column. We implement both because the difference is small (one branch in `jump_to_mark`) and removing it would surprise vim users.

### What counts as a "jump"

Vim's classic rule: anything that moves you across "regions" — searches, line jumps, marks, `%`, `(`, `)`, `{`, `}`. Not motion within a line (`h`, `l`, `0`, `$`) or single-line motion (`w`, `b`, `j`, `k`).

We start with the obvious set (`/`, `?`, `n`, `N`, `*`, `#`, `G`, `gg`, `:N`, mark jumps) and can extend later.

## Verification Plan

### Unit tests

`test/test_marks.rb`:

- `set('a', 3, 5)` then `get('a')` returns `[3, 5]`.
- `get('z')` (unset) returns nil.
- `'<` and `'>` resolve from `@last_visual` (mock the editor).
- Invalid name returns nil.

`test/test_editor.rb` additions:

- `m a` then `'a` jumps to the saved line.
- `Ctrl-O` after a search returns to the pre-search position.

### PTY end-to-end

1. `m a` on line 3, navigate elsewhere, `'a` returns to line 3 first-non-whitespace.
2. `m b` on line 5 col 4, `` `b `` returns to line 5 col 4 exactly.
3. After `/foo` Enter, `Ctrl-O` returns to pre-search position.
4. After several jumps, `Ctrl-O` walks back; `Ctrl-I` walks forward.
5. `'<` after a visual selection returns to selection start.
6. Setting two marks `'a` and `'b`, jumping between them, doesn't lose either.
7. After `:e other.txt`, `'a` from the previous file is no longer set (no-op or status).
8. `Ctrl-O` at empty jump list: silent no-op.
9. Invalid mark name (`'7` — digit, not letter): silent no-op.
10. `''` jumps back to the position before the last jump.

## Stages

1. **Mark storage** — `Rvim::Marks` (or inline Hash); `m{a-z}` set; `'a` line jump.
2. **Exact jump** — `` `a `` line+col jump; share waiting_proc dispatch.
3. **Jump list foundation** — `@jump_list`, `@jump_index`, `push_jump` from search / G / gg / `:N`.
4. **`Ctrl-O` / `Ctrl-I`** — bind, navigate index, tip-recording.
5. **Special marks** — `'<` / `'>` resolve from `@last_visual`; `''` / `` `` `` resolve from jump list.
6. **PTY end-to-end** — 10 scenarios; iterate.

Stretch:

- `:marks` listing (multi-line status display).
- `:jumps` listing.
- `'.` (last change), `'^` (last insert) — small addition once we track those positions.
