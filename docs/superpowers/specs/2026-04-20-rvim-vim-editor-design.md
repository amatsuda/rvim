# Rvim: Pure Ruby Vim Editor — Design Spec

## Context

Build a pure Ruby implementation of a NeoVim-compatible text editor, distributed as a gem (`rvim`). The editor subclasses `Reline::LineEditor` to leverage Reline's existing vi mode infrastructure (motions, operators, key dispatch, undo/redo, multi-line buffer) and adds full-screen rendering, file I/O, and ex commands on top.

This follows the same pattern as [rubish](https://github.com/amatsuda/rubish) — building a substantial application on top of Reline.

## Architecture

### Core Idea

`Reline::LineEditor` is already ~80% of a vi editor. It provides:
- `@buffer_of_lines` / `@line_index` / `@byte_pointer` — multi-line text buffer + cursor
- Vi key actors (`vi_insert`, `vi_command`) with full keybindings
- Operator + motion composability (`d`/`c`/`y` + motions with counts)
- Word motions (`w`, `b`, `e`, `W`, `B`, `E`), char search (`f`/`t`/`F`/`T`)
- `hjkl`, `0`, `$`, `^`, `x`, `p`, `P`, `r`, `J`, insert/append (`i`/`a`/`I`/`A`)
- Undo/redo history
- Escape sequence parsing via `Reline::KeyStroke`

We subclass it and:
1. **Override `render`** — replace inline rendering with full-screen ANSI output
2. **Remap `j`/`k`** — Reline maps these to history navigation; we need line navigation
3. **Add file I/O** — open, save, modified tracking
4. **Add command-line mode** — `:w`, `:q`, `:wq`, `:e`, `:N` (go to line)
5. **Add status line** — mode, filename, line/col, modified flag

### File Layout

```
exe/rvim                    # CLI entry point
lib/
  rvim.rb                   # Main require + version
  rvim/
    editor.rb               # < Reline::LineEditor — core editor class
    screen.rb               # Full-screen ANSI rendering
    command.rb              # Ex command parser & execution
rvim.gemspec
Gemfile
test/
  test_helper.rb
  test_editor.rb
  test_command.rb
```

Three source files to start. Extract modules as complexity demands.

### Dependencies

- `reline` (stdlib) — input handling, vi key dispatch, buffer management
- `io/console` (stdlib) — terminal size, raw mode support
- `test-unit` (dev) — testing

Zero external runtime dependencies.

## Components

### 1. Editor (`Rvim::Editor < Reline::LineEditor`)

The central class. Subclasses LineEditor to inherit all vi mode behavior.

**Initialization:**
- Set `@config.editing_mode = :vi_command` (start in normal mode, NeoVim default)
- Enable multiline mode (`multiline_on`)
- Load file contents into `@buffer_of_lines`
- Set up alternate screen buffer (smcup)

**Key remappings needed:**
- `j` / `k` — line navigation instead of history navigation. Override `ed_next_history` / `ed_prev_history` to move `@line_index` up/down within the buffer
- `G` — go to last line (override `vi_to_history_line`)
- `gg` — go to first line (implement via `@waiting_proc`: `g` sets a waiting proc, second `g` jumps to line 1)
- `:` — enter command-line mode (override or add binding)
- `o` / `O` — open line below/above (not mapped in Reline's vi_command; add as new methods)
- `ZZ` — save and quit
- `u` / `Ctrl-R` — undo/redo (Reline has `@undo_redo_history` + `@undo_redo_index` supporting both directions)

**File state:**
- `@filepath` — current file path (nil for new buffer)
- `@modified` — dirty flag (track via `input_key` override, comparing buffer state)

**Main loop:**
```ruby
def self.start(filepath = nil)
  editor = new(Reline.core.config)
  editor.open(filepath) if filepath

  Reline::IOGate.with_raw_input do
    loop do
      editor.render
      key = read_key  # via Reline's KeyStroke
      editor.update(key)
      break if editor.quit?
    end
  end
ensure
  editor&.cleanup  # restore terminal (rmcup)
end
```

### 2. Screen (`Rvim::Screen`)

Handles full-screen terminal rendering via ANSI escape sequences.

**Terminal setup/teardown:**
- Enter alternate screen buffer (`\e[?1049h`) on start
- Leave alternate screen buffer (`\e[?1049l`) on exit
- Hide/show cursor during redraws

**Rendering approach:**
- Get terminal size via `Reline::IOGate.get_screen_size` → `[rows, cols]`
- Usable area: `rows - 2` for text (reserve last 2 lines for status + command)
- Track `@scroll_top` — first visible line index
- Render visible lines with line numbers (optional, NeoVim default: `nonumber`)
- Use `output_modifier_proc` for future syntax highlighting

**Screen layout:**
```
+------------------------------------------+
| line 1 text                              |  ← @buffer_of_lines[@scroll_top]
| line 2 text                              |
| ...                                      |
| ~ (tilde for lines past EOF)             |  ← NeoVim-style empty line markers
+------------------------------------------+
| [Normal] filename.rb        3,15    25%  |  ← status line
| :w                                       |  ← command line (or empty)
+------------------------------------------+
```

**Differential rendering:**
- Track previously rendered lines
- Only redraw changed lines (like Reline's `render_differential`)
- Position cursor at correct screen location after render

### 3. Command (`Rvim::Command`)

Parses and executes ex commands entered via `:` in normal mode.

**Initial commands:**
| Command | Action |
|---------|--------|
| `:w [path]` | Save buffer to file |
| `:q` | Quit (fail if modified) |
| `:q!` | Force quit |
| `:wq` / `:x` | Save and quit |
| `:e path` | Open file |
| `:N` (number) | Go to line N |
| `:/pattern` | Search forward (stretch) |

**Implementation:**
- `:` key triggers command-line input mode
- Read characters into a command buffer, render at bottom of screen
- Enter executes, Esc cancels
- Parse command string and dispatch

## Key Technical Decisions

### j/k Remapping Strategy

Reline maps `j` → `ed_next_history` and `k` → `ed_prev_history` in vi_command mode. These navigate through readline history entries. For a text editor, we need these to move between lines in the buffer.

**Approach:** Override `ed_next_history` and `ed_prev_history` in the subclass to navigate `@line_index` within `@buffer_of_lines` instead of through history.

```ruby
private def ed_next_history(key)
  return if @line_index >= @buffer_of_lines.size - 1
  @line_index += 1
  # Adjust @byte_pointer to not exceed new line length
end

private def ed_prev_history(key)
  return if @line_index <= 0
  @line_index -= 1
  # Adjust @byte_pointer to not exceed new line length
end
```

### Command-Line Mode

`:` enters command-line mode. This is separate from Reline's normal key dispatch.

**Approach:** When `:` is pressed in normal mode, set a flag (`@command_mode = true`) and collect keystrokes into a command buffer. Render the command at the bottom of the screen. On Enter, parse and execute. On Esc, cancel.

This may require overriding `update(key)` to intercept keys when in command mode before they reach Reline's vi dispatch.

### Scroll Management

Override `scroll_into_view` to work with full-screen viewport:
- Keep cursor within the visible area (between `@scroll_top` and `@scroll_top + visible_lines - 1`)
- Scroll by adjusting `@scroll_top` when cursor moves out of view
- NeoVim-style: keep `scrolloff` lines of context (default: 0 for v1)

### Enter Key / Line Splitting

Reline's `key_newline` already handles splitting a line at cursor position in multiline mode. This gives us `o` (open line below) behavior for free — we just need to position the cursor at end-of-line first, then trigger newline, then enter insert mode.

## Verification Plan

### Manual Testing
1. `ruby -Ilib exe/rvim` — opens empty buffer, shows tilde lines
2. `ruby -Ilib exe/rvim test.txt` — opens file, displays contents
3. Navigate with `hjkl`, `w`, `b`, `0`, `$`, `gg`, `G`
4. `i` to enter insert mode, type text, `Esc` to return to normal
5. `dd` to delete a line, `p` to paste it
6. `:w test.txt` to save, `:q` to quit
7. `:wq` to save and quit
8. Verify undo with `u`

### Automated Tests (test-unit)
- `test_editor.rb` — buffer operations, cursor movement, mode switching
- `test_command.rb` — ex command parsing and execution
- Test buffer state after motion/operator sequences (e.g., `dw` on "hello world" → "world")

## Future Extensions (not in v1)
- Visual mode (characterwise, linewise, blockwise)
- Search (`/`, `?`, `n`, `N`)
- Multiple buffers / splits
- Syntax highlighting via `output_modifier_proc`
- `.vimrc` / init.lua style configuration
- Registers (named, numbered)
- Marks
- Text objects (`iw`, `i"`, `a(`, etc.)
- Macros (`q`, `@`)
- Repeat (`.`)
