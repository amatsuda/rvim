# Rvim v1.8: Syntax Highlighting + `:set` — Design Spec

## Context

Rvim has shipped seven major releases of editing primitives, but every line still renders as plain monochrome text. The biggest visual win we can deliver is syntax highlighting — token coloring driven by file type — and the `:set` infrastructure that lets users toggle it (along with line numbers, hlsearch, shiftwidth, etc.) at runtime.

This plan covers:

- **`:set` framework** — a small key/value settings store with ex-command parsing for `:set foo=bar`, `:set foo`, `:set nofoo`. A few common option name aliases (`nu`/`number`, `hls`/`hlsearch`, `sw`/`shiftwidth`).
- **Setting integration**:
  - `:set hlsearch` / `:set nohlsearch` — gate the search-match highlight rendering
  - `:set shiftwidth=N` — replace the hardcoded 2-space indent in `>>`/`<<`/visual `>`/`<`
  - `:set number` / `:set nonumber` — line-number gutter in window render
  - `:set relativenumber` / `:set norelativenumber` — gutter shows distance from cursor
- **Syntax highlighting** — regex-based tokenization, Ruby first. `:set syntax=ruby` / `:set syntax=off`. Auto-detect by file extension on `:e`.

Out of scope (deferred):

- Languages other than Ruby (a hook is in place; languages register themselves)
- Tree-sitter / Rouge — third-party syntax parsing
- `ignorecase` / `smartcase` for search
- `tabstop` (we currently render tabs as 8 spaces; would need to wire this through if we want it configurable)
- Heredoc / multi-line regex / `=begin`...`=end` blocks (token-level highlight is line-scoped)
- `expandtab` / `softtabstop` (we never insert tabs in the buffer; insert mode just types whatever the user types)

## Architecture

### `:set` parser

In `Rvim::Command.parse`, recognize a new verb `:set` with the rest of the line as the option string. Multiple options separated by space:

```
:set number hlsearch shiftwidth=2 syntax=ruby
```

Each token is one of:

- `name` — set the boolean to true (or `:on` for tri-state values)
- `noname` — set boolean to false
- `name=value` — set to value (parsed as integer if numeric, else string)
- `name?` — query (status message shows current value)

Pass through unknown names with an error: `E518: Unknown option: name` (vim's text).

### `Rvim::Settings`

Lightweight key/value store with defaults:

```ruby
class Rvim::Settings
  DEFAULTS = {
    hlsearch: true,
    shiftwidth: 2,
    number: false,
    relativenumber: false,
    syntax: :auto,    # :auto / :off / specific lang symbol like :ruby
  }.freeze

  ALIASES = {
    'hls' => :hlsearch, 'nu' => :number, 'rnu' => :relativenumber, 'sw' => :shiftwidth, 'syn' => :syntax
  }.freeze

  def initialize
    @options = DEFAULTS.dup
  end

  def get(name)
    @options[normalize(name)]
  end

  def set(name, value)
    @options[normalize(name)] = value
  end

  def normalize(name)
    sym = name.to_s
    ALIASES[sym] ? ALIASES[sym] : sym.to_sym
  end
end
```

`Editor.@settings = Rvim::Settings.new`. Existing read sites (`shiftwidth` in Operations.shift_right/shift_left, `hlsearch` in Screen render gating) consult `editor.settings.get(:foo)`.

### Syntax module shape

Per-language data tables keyed by symbol:

```ruby
module Rvim::Syntax
  TOKENS = {}    # { :ruby => [ {pattern: /.../, color: :magenta}, ... ], ... }

  def self.register(lang, tokens)
    TOKENS[lang] = tokens
  end

  def self.highlight(line, lang)
    return [] unless TOKENS[lang]

    out = []
    TOKENS[lang].each do |tok|
      offset = 0
      while (m = tok[:pattern].match(line, offset))
        b = m.pre_match.bytesize
        e = b + m[0].bytesize
        out << [b, e - 1, tok[:color]]
        offset = m.end(0)
      end
    end
    # If tokens overlap, last-write-wins; we sort by start, then drop overlaps
    # in favor of earlier (so the first definition wins on ties — comment first).
    coalesce(out)
  end

  def self.coalesce(segments)
    # Sort by start; drop any segment that overlaps a kept earlier one.
    sorted = segments.sort_by { |s, _e, _c| s }
    kept = []
    last_end = -1
    sorted.each do |s, e, c|
      next if s <= last_end

      kept << [s, e, c]
      last_end = e
    end
    kept
  end
end
```

Order matters: register more-specific patterns first (comments before keywords, strings before identifiers) so `coalesce` keeps them.

ANSI color codes:

```ruby
COLORS = {
  red:     "\e[31m", green:   "\e[32m", yellow:  "\e[33m",
  blue:    "\e[34m", magenta: "\e[35m", cyan:    "\e[36m",
  white:   "\e[37m", default: "\e[39m"
}
RESET = "\e[39m"
```

### Ruby tokens

```ruby
Rvim::Syntax.register(:ruby, [
  { pattern: /#[^\n]*/,                                   color: :cyan },     # comments
  { pattern: /"(?:\\.|[^"\\])*"/,                          color: :green },   # double-string
  { pattern: /'(?:\\.|[^'\\])*'/,                          color: :green },   # single-string
  { pattern: /`(?:\\.|[^`\\])*`/,                          color: :green },   # backtick
  { pattern: /\b(?:def|end|if|elsif|else|unless|while|until|for|do|case|when|then|return|class|module|begin|rescue|ensure|raise|yield|next|break|redo|retry|in|self|nil|true|false|and|or|not|require|require_relative)\b/, color: :magenta },
  { pattern: /:[A-Za-z_][A-Za-z_0-9]*[!?=]?/,             color: :yellow },   # symbols
  { pattern: /\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b/,      color: :red },     # numbers
  { pattern: /\b[A-Z][A-Za-z_0-9]*/,                      color: :blue },    # constants
])
```

Patterns are deliberately simple — no nested string interpolation, no heredocs, no regex literals. Single-line scope keeps the algorithm O(line × patterns) and avoids state.

### Screen integration

`render_window` per-line transformation gains a syntax pass:

```ruby
def render_with_syntax(line, line_index, win)
  segments = []
  if @editor.settings.get(:syntax) != :off
    lang = current_lang(win.buffer)
    segments = Rvim::Syntax.highlight(line, lang) if lang
  end
  return line if segments.empty?

  # Splice color escapes into the line, right-to-left
  out = line.dup
  segments.sort_by { |s, _e, _c| -s }.each do |s, e, color|
    head = out.byteslice(0, s) || +''
    mid = out.byteslice(s, e - s + 1) || +''
    tail = out.byteslice(e + 1, out.bytesize - e - 1) || +''
    out = head + Rvim::Syntax::COLORS[color] + mid + Rvim::Syntax::RESET + tail
  end
  out
end
```

Then layer selection/search highlights on top via the existing splice machinery. Color escapes survive the `\e[7m` / `\e[27m` reverse-video splices because they nest correctly (reset doesn't undo color, and the foreground stays through reverse-video).

### Line-number gutter

When `number` or `relativenumber` is on, prepend a fixed-width gutter to each rendered row. Width = `Math.log10(max_line)` + 2 (1 for spacing). Cursor positioning shifts by gutter width.

```ruby
def gutter_text(idx, cursor_idx, total)
  return '' unless @editor.settings.get(:number) || @editor.settings.get(:relativenumber)

  width = (Math.log10([total, 1].max).floor + 1).clamp(2, 6) + 1
  if @editor.settings.get(:relativenumber) && idx != cursor_idx
    "%#{width}d " % (idx - cursor_idx).abs
  else
    "%#{width}d " % (idx + 1)
  end
end
```

The gutter is rendered with a dim foreground color so it doesn't compete with content.

### File layout (additive)

```
lib/rvim/
  settings.rb       # NEW — Rvim::Settings
  syntax.rb         # NEW — Rvim::Syntax (registry + highlight)
  syntax/
    ruby.rb         # NEW — registers Ruby tokens
  command.rb        # parse / execute :set
  editor.rb         # @settings, expose; auto-detect syntax on open
  screen.rb         # syntax color splicing; line-number gutter
  operations.rb     # shift_right/shift_left read shiftwidth from settings
test/
  test_settings.rb
  test_syntax.rb
```

## Components

### 1. `Rvim::Settings`

As above. Three operations: `get`, `set`, normalize-with-aliases.

### 2. `:set` parsing

```ruby
SET_RE = %r{\A(no)?(\w+)(?:=(\S+))?\z}

def self.parse_set(args)
  args.to_s.split(/\s+/).map do |tok|
    next unless tok.match?(SET_RE)
    m = tok.match(SET_RE)
    name = m[2]
    if m[1] == 'no'
      [name, false]
    elsif m[3]
      val = m[3].match?(/\A\d+\z/) ? m[3].to_i : m[3]
      [name, val]
    else
      [name, true]
    end
  end.compact
end
```

`execute_set(editor, parsed)`:

```ruby
parsed.set_options.each do |name, value|
  editor.settings.set(name, value)
  syntax_changed if name == 'syntax' || name == 'syn'
end
```

### 3. Auto-detect language on `:e`

```ruby
def detect_language(filepath)
  return nil unless filepath
  case File.extname(filepath)
  when '.rb', '.gemspec', '.rake' then :ruby
  end
end
```

When `settings[:syntax] == :auto`, Screen consults `detect_language(buffer.filepath)`. When set to `:ruby` explicitly, force; when `:off`, skip.

### 4. Search highlight gate

In `Screen#render_window`, only call `apply_search_highlight` when `@editor.settings.get(:hlsearch)` is true. Search prompt incremental highlight ignores hlsearch (always shown while typing — matches vim).

### 5. Shiftwidth

`Rvim::Operations.shift_right(editor, sel, count: 1)`:

```ruby
shiftwidth = editor.settings.get(:shiftwidth)
indent = ' ' * (shiftwidth * count)
```

Same for `shift_left` and the normal-mode `>>`/`<<` paths in Editor.

### 6. Line-number gutter

In `render_window`, compute gutter width once per window (based on buffer's total lines). Each rendered row gets a prefix; `win.width` for content shrinks by gutter width. Cursor X also shifts.

## Key Technical Decisions

### Why regex-based, not Rouge

Rouge is a high-quality syntax library with full Ruby support. Adding it is a runtime dependency we've avoided everywhere else. Regex tokenizers are ~50 lines per language and produce 80% of the visual benefit. If users demand more accurate highlighting, we can wire Rouge as an opt-in module later.

### Token order and overlap

Order in the token list matters: `coalesce` keeps the *first* segment that starts at a given offset. So put comments before keywords, strings before identifiers. The current Ruby table is ordered correctly.

A `def` keyword inside a string `"def"` is *correctly* not highlighted because the string segment covers the bytes first.

### Render-time vs cached

We highlight lines on every render. For 24 visible rows × ~9 patterns × short regex match work, this is fast (microseconds). If profiling shows it as a bottleneck, cache by `(line, language)` and invalidate on buffer change.

### Color escape interaction with selection

When a selection covers a colored token, the splice order is:

1. Syntax color escape `\e[33m...mid...\e[39m`
2. Reverse video escape wraps the whole selected region: `\e[7m...colored...\e[27m`

This composes correctly in most terminals — reverse video doesn't cancel color. Some terminals show the inverted background of the colored text, which is exactly the visual we want.

### `:set` doesn't need `:setlocal` / global scope

Vim has `setlocal` for buffer-scoped options. We treat all settings as global for v1.8 — simpler, and 90% of the win. Per-buffer settings (e.g., different shiftwidth in different files) come later.

## Verification Plan

### Unit tests

`test/test_settings.rb`:

- `set('number', true)` then `get('number')` returns `true`.
- `set('nu', false)` resolves the alias and updates the canonical key.
- Default `get(:shiftwidth)` returns 2.

`test/test_syntax.rb`:

- `Syntax.highlight('# comment', :ruby)` returns one segment with `:cyan`.
- `Syntax.highlight('def foo', :ruby)` highlights `def` as keyword.
- `Syntax.highlight('puts "hello"', :ruby)` highlights `"hello"` as string and `puts` not (puts isn't in the keyword list — that's fine).
- Overlap: `def "def"` highlights `def` keyword and string `"def"` separately, not nested.

`test/test_command.rb`:

- `Rvim::Command.parse(':set number')` populates the `set` field.
- `Rvim::Command.parse(':set sw=4')` parses to `[['sw', 4]]`.
- `Rvim::Command.parse(':set nohlsearch')` parses to `[['hlsearch', false]]`.

### PTY end-to-end

1. `:set number` then a render — line numbers visible in gutter.
2. `:set nonumber` removes them.
3. `:set hlsearch` then `/foo` — matches highlighted; `:set nohlsearch` clears.
4. `:set shiftwidth=4` then `>>` — line indented by 4 spaces.
5. `:set syntax=ruby` on a `.rb` file — `def`, strings, comments are colored.
6. `:set nosyntax` removes colors.
7. Auto-detect on `:e foo.rb` — colors appear without explicit `:set`.
8. `:set foo` (unknown) — status message E518.
9. Selection over colored text — both highlights compose visually.
10. `:set sw=8 number hlsearch` — multiple options in one line all apply.

## Stages

1. **`Rvim::Settings`** — class with defaults, get/set, alias normalization. Tests.
2. **`:set` parser + executor** — extend `Command::Parsed`; parse `name`/`noname`/`name=value`; `execute_set` writes to `editor.settings`.
3. **`hlsearch` integration** — Screen gates `apply_search_highlight` by setting; defaults to true.
4. **`shiftwidth` integration** — Operations.shift_right/_left and normal-mode >>/<< read setting.
5. **Line-number gutter** — `:set number`, `:set relativenumber`, render gutter, shrink content width, shift cursor.
6. **`Rvim::Syntax` foundation** — module + `highlight(line, lang)` + ANSI colors. Stub language registry.
7. **Ruby tokenizer** — define the patterns; register on load.
8. **Syntax render integration** — Screen splices color escapes; auto-detect by extension on `:e`; `:set syntax=ruby/off/auto`.
9. **PTY end-to-end** — 10 scenarios; iterate.

Stretch:

- Additional languages (Markdown, JSON, shell).
- `:set ignorecase` / `smartcase` for search.
- Cache highlighted lines by `(line, lang, version)` if rendering shows up in a profile.
- Per-buffer `setlocal` scope.
