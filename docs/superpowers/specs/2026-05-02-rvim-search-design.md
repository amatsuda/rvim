# Rvim v1.3: Search + Substitute — Design Spec

## Context

v1.2 wraps up the editing primitives (operators + motions + text objects). Search is the next missing piece: vim's `/`, `?`, `n`, `N`, `*`, `#` are core navigation, and `:s/old/new/` is one of the most-used commands in any text editor. Adding these unlocks a major class of workflows that aren't possible today.

This plan covers:

- `/<pattern>` — forward search with incremental highlight while typing
- `?<pattern>` — backward search
- `n` / `N` — next / previous match (in search direction / opposite)
- `*` / `#` — search forward / backward for the word under the cursor
- `:s/old/new[/g]` — substitute on current line
- `:%s/old/new/[g]` and `:N,Ms/...` — substitute over a range
- Visual-mode `:s` — substitute applied to the selection only

Out of scope (deferred):

- `:set hlsearch` / `:set nohlsearch` (needs `:set` infrastructure)
- `gn` / `gN` (visual-select last match) — small, follow-up plan
- `\v` / `\V` magic toggles — Ruby's Regexp default is pretty close to vim's `magic`, good enough
- `&` to repeat last substitute
- `:s/.../[c]` interactive confirm

## Architecture

### Search vs. command-line: the input pipeline

`:`, `/`, and `?` all enter a single-line input mode at the bottom of the screen. v1's `@command_mode`/`@command_buffer` works for `:`, but `/` and `?` need:

1. **Different prefix glyph** rendered in the prompt (`/`, `?`, vs. `:`).
2. **Incremental side effect**: while the user types, we want to highlight matches *as they type*. Plain `:` has no such side effect.
3. **Different terminator behavior**: Enter on `/foo` *jumps* to the first match (and saves the pattern); Enter on `:wq` parses-and-executes ex commands.

To avoid splitting `command_mode` into three branches, generalize:

```ruby
@prompt_mode      # nil | :ex | :search_forward | :search_backward
@prompt_buffer    # the typed text after the prefix glyph
```

Replaces v1's `@command_mode` (boolean) and `@command_buffer`. Existing call sites that read `editor.command_mode` migrate to `editor.prompt_mode == :ex`. Everywhere else, the screen and process loop branch on `prompt_mode`.

`process_prompt_key(key)` is the single entry point for prompt-mode keystrokes. Inside, it dispatches by `@prompt_mode`:

| `@prompt_mode`        | Enter behavior                                                  | While typing                        |
|-----------------------|-----------------------------------------------------------------|-------------------------------------|
| `:ex`                 | `Rvim::Command.parse(buffer)` → `execute`                       | nothing                             |
| `:search_forward`     | save pattern, jump to first match forward, `@search_dir = :fwd` | run search, update highlight matches |
| `:search_backward`    | save pattern, jump to first match backward, `@search_dir = :bwd` | same                                |

### Search state

```ruby
@search_pattern     # String, last successful search pattern (for n/N/*/#)
@search_direction   # :forward | :backward
@search_matches     # Array of [line, byte_start, byte_end] across the buffer
@hlsearch           # Boolean (default true), highlight all matches
```

`@search_matches` is recomputed:
- Whenever `@search_pattern` changes (from prompt commit, from `*`/`#`, from `:s`).
- Whenever the buffer changes — but not too eagerly. Recompute on render demand: if buffer has been modified since last match scan, rescan before rendering. (We can hash the buffer or track a dirty flag.)

### Where matches get highlighted

Screen render walks `editor.search_matches` and inverse-videoes each match cell, the same way visual selection does. Visual highlight wins over search highlight when they overlap (selection takes precedence; we render visual after search).

A match that crosses lines isn't allowed (vim doesn't either, by default — `/foo\nbar` would need `\_.` magic which we skip). Each match is a single `(line, byte_start, byte_end)` tuple.

### File layout (additive)

```
lib/rvim/
  search.rb           # NEW — Search.scan(buffer, pattern, dir) -> Array of matches
                      #       Search.next_match(matches, line, col, dir)
  command.rb          # extended: parse :s and :%s, return new Parsed shape
  editor.rb           # @prompt_mode/@prompt_buffer, search bindings,
                      # incremental highlight on prompt keystroke
  screen.rb           # render search highlights; render the prompt prefix
                      # by mode
test/
  test_search.rb      # NEW — scan, next/prev, regex variants
  test_command.rb     # add :s and :%s parser tests + execute
  test_editor.rb      # prompt-mode migration tests
```

## Components

### 1. `Rvim::Search`

Pure-data module — no editor coupling.

```ruby
module Rvim::Search
  def self.scan(buffer_of_lines, pattern_str)
    pattern = compile(pattern_str)
    return [] unless pattern

    out = []
    buffer_of_lines.each_with_index do |line, line_idx|
      offset = 0
      while (m = pattern.match(line, offset))
        b = m.byte_begin(0)
        e = m.byte_end(0)
        if e == b
          # Avoid infinite loop on zero-width matches
          offset = b + 1
        else
          out << [line_idx, b, e - 1]  # end_col is inclusive
          offset = e
        end
      end
    end
    out
  end

  def self.next_match(matches, line, col, direction)
    return nil if matches.empty?

    case direction
    when :forward
      matches.find { |l, s, _| l > line || (l == line && s > col) } || matches.first
    when :backward
      matches.reverse_each.find { |l, _, e| l < line || (l == line && e < col) } || matches.last
    end
  end

  def self.compile(pattern_str)
    Regexp.new(pattern_str)
  rescue RegexpError
    nil
  end
end
```

Wraparound (`/foo` past EOF returns to top) is built in via the `|| matches.first` fallback.

### 2. Prompt mode plumbing (Editor)

Replace the `@command_mode` boolean with `@prompt_mode` symbol. Migration:

- `def command_mode; @prompt_mode == :ex; end` for backward compat with `Screen` (so we don't break existing render code on the way through).
- `process_command_key` becomes `process_prompt_key`; the body branches on `@prompt_mode` for the Enter behavior.
- Existing `:` binding sets `@prompt_mode = :ex`; new `/` and `?` bindings set `@prompt_mode = :search_forward` / `:search_backward`.

While in search prompt mode, after each keystroke, recompute `@search_matches = Search.scan(@buffer_of_lines, @prompt_buffer)`. Render highlights everything live.

On Enter:
- Save `@prompt_buffer` to `@search_pattern`.
- `@search_direction = (@prompt_mode == :search_forward) ? :forward : :backward`.
- Find next match from cursor; jump to it. If no match, status message: `E486: Pattern not found: <pat>`.
- Reset `@prompt_mode = nil`, `@prompt_buffer = ''`.

On Esc:
- Reset `@prompt_mode`, `@prompt_buffer`, **and** clear `@search_matches` (the typed-but-not-committed pattern shouldn't keep highlighting).

### 3. `n` / `N` / `*` / `#` (Editor)

Bindings in `vi_command`:

- `n` → if `@search_pattern`, find next match in `@search_direction` from cursor; jump.
- `N` → same but in opposite direction.
- `*` → grab `\<word\>` at cursor (use the same word-class scanner from `TextObject.word`), set `@search_pattern`, `@search_direction = :forward`, jump to next match.
- `#` → same but `:backward`.

`*` and `#` use `\b<word>\b` boundary syntax so `foo*` matches `foo` but not `foobar`.

### 4. `:s/old/new[/g]` (Command)

Extend `Rvim::Command::Parsed` and `parse`:

```ruby
Parsed = Struct.new(:verb, :arg, :bang, :line_number, :range, :sub, keyword_init: true)
# sub: { pattern:, replacement:, global: }
```

Range syntax to parse (in this plan):

- Empty → current line only.
- `%` → whole file (lines `0..size-1`).
- `N,M` → line range.
- `'<,'>` → visual selection — implemented as a *special* range that the editor resolves via `@last_visual`.

Parser handles delimiter `/`. Vim allows other delimiters (`:s#a#b#`) but skip those for v1 — `/` is enough.

Execute:

```ruby
def self.execute_substitute(editor, parsed)
  pattern = Regexp.compile(parsed.sub[:pattern])
  replacement = parsed.sub[:replacement]
  global = parsed.sub[:global]
  start_line, end_line = resolve_range(editor, parsed.range)
  count = 0
  (start_line..end_line).each do |i|
    line = editor.buffer_of_lines[i]
    new_line = global ? line.gsub(pattern) { count += 1; replacement } : line.sub(pattern) { count += 1; replacement }
    editor.buffer_of_lines[i] = new_line
  end
  editor.status_message = "#{count} substitution#{count == 1 ? '' : 's'}"
end
```

Error handling: invalid regex → status message `E383: Invalid search string: <pat>`, no buffer change.

### 5. Visual mode `:s` (Editor)

When the user is in visual mode and presses `:`, the prompt opens preloaded with `'<,'>` (vim convention). Implementation: in the `:` binding, if `@visual_mode` is set, exit visual and pre-fill `@prompt_buffer = "'<,'>"`. The `Command.parse` then sees that range and resolves it via `@last_visual`.

### 6. Search highlight rendering (Screen)

In `render`, after computing the visual selection highlight (which wins), walk `editor.search_matches` for the current visible row range and inverse-video each match's bytes — only for matches not already covered by the visual selection.

If `@hlsearch` is false (set via future `:set` command, defaulted to `true` for v1.3), skip highlighting. Always highlight matches that are being incrementally typed in the search prompt regardless of `@hlsearch`.

### 7. Buffer-change invalidation

Searches go stale when the buffer is edited. Strategy:

- Bump a `@buffer_revision` integer in `update` whenever `before != @buffer_of_lines`.
- Cache `@search_matches_revision = revision_at_scan_time`.
- Before rendering, if `@search_pattern` is set and `@buffer_revision != @search_matches_revision`, rescan.

This keeps rescans lazy (only when we actually need to render highlights).

## Key Technical Decisions

### Regex: Ruby's `Regexp` directly

vim's regex flavor differs from PCRE/Ruby in details (`\<`, `\>` for word boundaries, `\(\)` for groups in default `magic`, etc.). Translating perfectly is out of scope. Document the choice and accept Ruby's `\b`/`(...)`/`*` syntax — most users get what they want.

For `*` and `#` (word search), construct the pattern as `\b<word>\b` after escaping word chars with `Regexp.escape`. This means a literal word search, not regex-interpreted user input — the right call.

### Why `:` vs `/` differ in handling

`:` is a *batched* command — nothing happens until Enter. `/` is *incremental* — every keystroke updates `@search_matches`. The unified `process_prompt_key` checks `@prompt_mode` and only triggers a search rescan when in `:search_*` modes:

```ruby
def process_prompt_key(key)
  # ... shared input handling (Enter, Esc, backspace, char append) ...
  # After buffer mutation:
  refresh_search_matches if @prompt_mode != :ex
end
```

### Visual `'<,'>` resolution

When `Command.parse` sees a range token of `'<,'>`, it returns `range: :visual` and `execute` uses `@last_visual` to compute the line span. `@last_visual` is already set by visual mode exit (Stage 7 of v1.1). For an even-better experience, pre-fill the prompt buffer when `:` is pressed in visual mode.

### Lazy rescan

A buffer with 10K lines + a search pattern that matches a thousand times shouldn't run `Search.scan` on every keystroke. Lazy rescan only when render needs the matches and the buffer revision has changed. For the prompt-incremental case the user is typing the pattern, not the buffer, so the buffer revision doesn't change → no churn.

## Verification Plan

### Unit tests

`test/test_search.rb`:

- `scan` returns matches in order, with correct byte offsets.
- Multibyte (e.g., Japanese) text is matched correctly with `\b` boundaries — actually, `\b` is ASCII-only; document and test with Latin chars only or use `\b` carefully.
- Zero-width pattern (`/^/`) doesn't infinite-loop.
- Invalid regex returns no matches, no exception.
- `next_match` wraps around past EOF / before BOF.
- `next_match` from match position: forward goes to next, not the same.

`test/test_command.rb` additions:

- `:s/foo/bar/` parses with correct verb/sub.
- `:s/foo/bar/g` parses with global.
- `:%s/...` parses with range = `:whole`.
- `:5,10s/...` parses with range = `[5, 10]`.

`test/test_editor.rb` additions:

- Pressing `/` opens prompt with mode `:search_forward`.
- Typing in search prompt updates `@search_matches` live.
- Enter on `/foo` jumps cursor to first match and saves pattern.
- `n` after a search jumps to next match.
- `*` from cursor on a word builds `\bword\b` pattern.

### PTY end-to-end

1. `/foo` then Enter — cursor jumps to first match, status shows match found.
2. `n` after `/foo` — cursor advances to next match.
3. `?bar` — cursor jumps backward to previous match.
4. `*` on a word — cursor jumps to next occurrence of that word.
5. `:s/old/new/` on a line containing `old old` — only first occurrence replaced.
6. `:s/old/new/g` — both replaced.
7. `:%s/foo/bar/g` — all `foo` across buffer become `bar`.
8. `:5,7s/x/y/g` — only lines 5-7 affected.
9. Visual select 3 lines, `:s/x/y/g` — only those lines affected (`'<,'>` resolution).
10. `/regex(missing` — invalid regex, status message, no crash.

## Stages

1. **`Rvim::Search` foundation** — `scan`, `next_match`, regex compile-with-fallback. Unit tests.
2. **Prompt mode generalization** — replace `@command_mode` with `@prompt_mode` symbol; keep ex behavior identical. No new bindings yet.
3. **`/` and `?` prompt entry** — bindings; Enter saves pattern, jumps. No incremental highlight yet.
4. **Search match rendering** — Screen highlights `@search_matches` after a search committed.
5. **Incremental highlight while typing** — recompute matches on each search-prompt keystroke; clear on Esc.
6. **`n` / `N`** — repeat search using `@search_pattern` and `@search_direction`.
7. **`*` / `#`** — word-under-cursor search.
8. **`:s/old/new[/g]` on current line** — extend `Command::Parsed`, parse, execute.
9. **`:%s` / `:N,Ms` ranges** — range parser, execute over span.
10. **Visual `:s` with `'<,'>`** — pre-fill prompt buffer, resolve range from `@last_visual`.
11. **PTY end-to-end** — run all 10 verification scenarios; iterate.

Stretch:

- `:set hlsearch` / `:set nohlsearch` (needs `:set` framework — defer).
- `gn` / `gN` for visual-select last match.
