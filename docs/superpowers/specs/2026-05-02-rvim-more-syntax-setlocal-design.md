# Rvim v1.9: More Syntax Languages + `:setlocal` — Design Spec

## Context

v1.8 shipped Ruby syntax highlighting and a global `:set` framework. Two natural follow-ups land in v1.9:

1. **Three more language tokenizers** — Markdown, JSON, Shell — using the existing `Rvim::Syntax.register` plumbing.
2. **`:setlocal` per-buffer settings** — different `shiftwidth`, `syntax`, etc. per file type. Vim's bread and butter for editing mixed projects.

Plus auto-detection extensions so opening `foo.md` lights up Markdown highlighting without `:set syntax=markdown`.

Out of scope (deferred):

- Multi-line tokens (Markdown code fences spanning lines, shell heredocs, JSON multi-line strings — same restriction as Ruby in v1.8)
- Filetype plugins / `ftdetect` directives
- Languages beyond these three (Python, JavaScript, YAML, ...)
- `:setlocal!` to reset to global default

## Architecture

### Per-buffer settings

`Rvim::Buffer` gains a `@local_settings` Hash. `Rvim::Settings#get(name)` is extended to consult the current buffer's local overlay before the global table:

```ruby
class Rvim::Settings
  def initialize
    @options = DEFAULTS.dup
  end

  def get(name, buffer: nil)
    key = normalize(name)
    if buffer && buffer.local_settings.key?(key)
      buffer.local_settings[key]
    else
      @options[key]
    end
  end

  def set(name, value, buffer: nil)
    key = normalize(name)
    if buffer
      buffer.local_settings[key] = value
    else
      @options[key] = value
    end
    key
  end
end
```

Editor exposes a `current_settings_get(name)` helper that passes `buffer: @current_buffer`. Existing call sites that read `editor.settings.get(:foo)` get auto-routed through this helper. Or — simpler — `editor.settings.get(:foo)` itself defaults `buffer: @current_buffer` when omitted.

### `:setlocal` parser

Add a new verb. Just like `:set` but routed with `local: true`:

```ruby
when 'setlocal', 'setl' then :setlocal
```

`execute_setlocal(editor, parsed)` walks `set_options` and calls `editor.settings.set(name, value, buffer: editor.current_buffer)`.

### Language tokenizer additions

Three new files under `lib/rvim/syntax/`. Each registers itself on require, same as `ruby.rb`:

- `lib/rvim/syntax/markdown.rb` — headings, code spans, links, bold/italic, list markers
- `lib/rvim/syntax/json.rb`     — strings, numbers, true/false/null
- `lib/rvim/syntax/shell.rb`    — comments, strings, variables, keywords, numbers

`detect_language` extends to:

```ruby
def self.detect_language(filepath)
  return nil unless filepath
  case File.extname(filepath)
  when '.rb', '.gemspec', '.rake' then :ruby
  when '.md', '.markdown'         then :markdown
  when '.json'                    then :json
  when '.sh', '.bash', '.zsh'     then :shell
  end
end
```

### File layout (additive)

```
lib/rvim/
  buffer.rb            # add @local_settings = {}
  settings.rb          # buffer: kwarg on get/set
  command.rb           # :setlocal parser/executor
  editor.rb            # default buffer: in settings access
  syntax/
    markdown.rb        # NEW
    json.rb            # NEW
    shell.rb           # NEW
  syntax.rb            # extend detect_language
test/
  test_syntax_markdown.rb
  test_syntax_json.rb
  test_syntax_shell.rb
```

## Components

### 1. Markdown tokens

```ruby
Rvim::Syntax.register(:markdown, [
  # Code spans first so backticks dominate over emphasis markers.
  { pattern: /`[^`]+`/,                              color: :green },
  # Headings (1-6 #s at start of line; the whole line through to EOL).
  { pattern: /^#{1,6}\s.*$/,                         color: :magenta },
  # Bold ** ** must come before italic * * to win on overlap.
  { pattern: /\*\*[^*]+\*\*/,                        color: :magenta },
  # Italic.
  { pattern: /\*[^*\n]+\*/,                          color: :yellow },
  # Links: [text](url)
  { pattern: /\[[^\]]*\]\([^)]*\)/,                  color: :cyan },
  # Bullet markers at start of line.
  { pattern: /^\s*[-*+]\s/,                          color: :yellow },
  # Horizontal rule.
  { pattern: /^[-=*]{3,}\s*$/,                       color: :yellow },
])
```

Edge cases acknowledged: nested emphasis (`**foo *bar* baz**`) renders as bold over the whole span — italic markers inside are eaten. Acceptable for v1.9.

### 2. JSON tokens

```ruby
Rvim::Syntax.register(:json, [
  # Strings (used for both keys and values; we don't differentiate).
  { pattern: /"(?:\\.|[^"\\])*"/,                    color: :green },
  # Numbers including negative, exponent, decimal.
  { pattern: /-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/, color: :red },
  # Literals.
  { pattern: /\b(?:true|false|null)\b/,              color: :magenta },
])
```

We could split keys from values by lookahead (`"key"\s*:`) but the gain isn't worth the regex complexity.

### 3. Shell tokens

```ruby
Rvim::Syntax.register(:shell, [
  # Comments first to dominate everything else.
  { pattern: /#[^\n]*/,                              color: :cyan },
  # Strings (double and single).
  { pattern: /"(?:\\.|[^"\\])*"/,                    color: :green },
  { pattern: /'[^']*'/,                              color: :green },
  # Variables: $foo, ${foo}, $1.
  { pattern: /\$\{[^}]+\}/,                          color: :yellow },
  { pattern: /\$\w+|\$[!?@#*$]/,                     color: :yellow },
  # Keywords.
  { pattern: /\b(?:if|then|elif|else|fi|for|while|until|do|done|in|case|esac|function|return|exit|local|export|readonly|set|unset)\b/, color: :magenta },
  # Numbers.
  { pattern: /\b\d+\b/,                              color: :red },
])
```

Single-quoted strings can't contain escape sequences in shell, so the regex is simpler than for double quotes.

### 4. `:setlocal` integration

Existing settings reads happen through `editor.settings.get(:name)`. Default the `buffer:` kwarg to `editor.current_buffer` so any read automatically picks up local-or-global. Writes via `:set` skip `buffer:` (global); `:setlocal` passes `buffer: editor.current_buffer`.

`Rvim::Buffer.new` initializes `@local_settings = {}`. Cleared automatically when the buffer is removed via `:bd`.

The `syntax` setting is the most natural use case: `.json` files get `:setlocal syntax=json` automatically via the existing detection path. The detection now also writes a buffer-local override so a file's syntax setting persists if the user runs `:set syntax=off` globally — only the file they had explicit detection for gets re-detected.

Actually, simpler: keep `:syntax` as a global default, and let `current_language` (in Screen) consult `Syntax.detect_language(buffer.filepath)` when the global is `:auto`. We don't need `:setlocal syntax=foo` to be the auto-detection mechanism — `auto` does the right thing already. `:setlocal` shines for `shiftwidth` (project A uses 2, project B uses 4).

## Key Technical Decisions

### Per-buffer settings live on `Buffer`, not `Settings`

The alternative is to keep all overlays in a `Hash<buffer_id, Hash>` on `Settings`. That's more central but couples `Settings` to the `Buffer` lifecycle. Putting `@local_settings` on `Buffer` itself keeps each Buffer self-contained and makes `:bd` cleanup automatic.

### Scope of `:setlocal` defaults

We don't track "is this option locally set" vs "set to the global default value" separately. Setting `:setlocal sw=2` writes 2 to the buffer's overlay; if the global was already 2, the overlay is redundant. That's fine — `get` always finds it. To clear: `:set` (global) — for v1.9 we don't ship `:setlocal!` to clear an overlay back to global.

### Markdown emphasis ordering

`**bold**` and `*italic*` overlap textually. Registering `**` first and using `coalesce` (which keeps earliest-starting) means `**foo**` is bold; `*foo*` is italic. A line containing both — `*one* **two**` — gets two segments correctly because they don't overlap.

But `**foo *italic* bar**` will render the whole span as bold (italic markers are inside). Vim's markdown ftplugin treats this similarly. Good enough.

### Why no per-language line-break rules?

Markdown headings span just one line. Shell heredocs span multiple. JSON strings can technically span lines but it's invalid JSON. We stay single-line for all of them in v1.9 and accept that heredocs and rare multi-line strings show partly correctly.

## Verification Plan

### Unit tests

`test/test_syntax_markdown.rb`:

- `# Heading` → magenta segment covering the line.
- `` `code span` `` → green.
- `**bold**` → magenta.
- `*italic*` → yellow.
- `[text](url)` → cyan.

`test/test_syntax_json.rb`:

- `"key": "value"` → two green segments.
- `42` → red.
- `true`, `false`, `null` → magenta.

`test/test_syntax_shell.rb`:

- `# comment` → cyan.
- `"hi"` → green.
- `$foo` → yellow.
- `if then fi` → three magenta keyword segments.

`test/test_settings.rb`:

- `set(:sw, 4, buffer: b)` then `get(:sw, buffer: b)` returns 4 even if global is 2.
- `get(:sw, buffer: b2)` (different buffer) returns global 2.

### PTY end-to-end

1. Open `.md` file → headings rendered magenta.
2. Open `.json` file → numbers red, booleans magenta.
3. Open `.sh` file → keywords magenta, variables yellow.
4. `:set sw=2` then `:setlocal sw=8` in buffer A → `>>` indents 8 in A.
5. `:bn` to buffer B → `>>` indents 2 (global).
6. `:bn` back to A → `>>` still indents 8.
7. `:setlocal syntax=ruby` on a `.txt` file forces Ruby colors there only.
8. `:set syntax=off` globally; `:setlocal syntax=ruby` on one buffer keeps it colored.
9. `:setlocal foo` (unknown) → E518.
10. Auto-detection: `:e foo.md` colors headings; `:e bar.json` colors strings/numbers.

## Stages

1. **`:setlocal` framework** — Buffer.@local_settings; Settings.get/set with `buffer:` kwarg; default to current_buffer; parser/executor for `:setlocal`. Tests.
2. **Markdown tokenizer** — `lib/rvim/syntax/markdown.rb`; `.md`/`.markdown` extension routing; tests.
3. **JSON tokenizer** — `lib/rvim/syntax/json.rb`; `.json` extension; tests.
4. **Shell tokenizer** — `lib/rvim/syntax/shell.rb`; `.sh`/`.bash`/`.zsh` extension; tests.
5. **PTY end-to-end** — 10 scenarios; iterate.

Stretch:

- `:setlocal!` (clear local override).
- Python / YAML / JavaScript tokenizers.
- Filetype plugin hooks (`ftdetect` style).
