# Rvim v1.7: Multiple Buffers + Window Splits — Design Spec

## Context

Today rvim is single-buffer, single-window. Every editor instance owns one `@buffer_of_lines`, one cursor, one viewport. This plan adds the two architectural pieces that turn rvim into a real multi-file editor:

1. **Buffers** — a registry of open files, switchable via `:e`/`:bn`/`:bp`/`:b{n}`/`:bd`. Each buffer keeps its own lines, marks, undo history, modified flag, and last-visual state.
2. **Windows (splits)** — horizontal (`:sp`/`Ctrl-W s`) and vertical (`:vsp`/`Ctrl-W v`). Each window shows one buffer with its own cursor and viewport. Navigation via `Ctrl-W h/j/k/l`.

Plus the deferred prerequisite that arrives with this plan:

3. **Global marks `m{A-Z}`** — store `[buffer_id, line, col]`; `'A` / `` `A `` jumps to that file, switching buffers if needed.

Out of scope (deferred):

- `:ls` / `:buffers` listing (needs the listing-UI framework — separate plan)
- Window resize (`Ctrl-W +` / `Ctrl-W -` / `Ctrl-W <` / `Ctrl-W >`)
- Window equalize (`Ctrl-W =`)
- Tab pages (`:tabnew`)
- `:sb` (split with buffer)
- Per-window cursor when two windows view the same buffer (we share the cursor across windows on the same buffer; vim keeps them separate — match later)

## Architecture

### `Rvim::Buffer`

Carves out everything currently per-instance on Editor that's tied to file content:

```ruby
class Rvim::Buffer
  attr_accessor :id, :filepath, :lines, :modified
  attr_accessor :marks                 # local marks (a-z)
  attr_accessor :undo_redo_history, :undo_redo_index
  attr_accessor :last_visual           # for '<, '>, gv
  attr_accessor :line_index, :byte_pointer  # last cursor position in this buffer

  # Constructor reads the file or starts empty.
  def initialize(id, filepath = nil) ; ... ; end
end
```

Cursor on the buffer is a per-buffer "where I last was when this buffer was active." Windows that show the same buffer share it (simplification noted above).

### Buffer registry on `Editor`

```ruby
@buffers = {}        # id (Integer) -> Buffer
@buffer_order = []   # [id, ...] insertion order, for :bn / :bp navigation
@current_buffer = nil  # Buffer reference (active buffer)
```

When the active buffer changes, `Editor` must save its current `@buffer_of_lines` / `@line_index` / `@byte_pointer` / `@modified` / `@marks` / `@last_visual` / `@undo_redo_history` / `@undo_redo_index` / `@filepath` into the *outgoing* buffer record, then load those values from the incoming record. A `swap_to(buffer)` helper handles both halves atomically.

The cleanest factoring: keep Reline-facing ivars (`@buffer_of_lines`, `@line_index`, `@byte_pointer`, `@undo_redo_history`, `@undo_redo_index`) on Editor as *aliases* that mirror `@current_buffer`'s fields. Reline reads them; we write through.

### `Rvim::Window`

Each visible pane:

```ruby
class Rvim::Window
  attr_accessor :buffer            # Buffer reference
  attr_accessor :scroll_top        # viewport offset
  attr_accessor :row, :col, :height, :width  # screen position (set by layout)
  # Cursor lives on Buffer for now (see "out of scope")
end
```

Editor maintains a list of open windows plus a "current window" pointer:

```ruby
@windows = []         # [Window, ...]
@current_window = nil
```

### Layout — flat split list

Real vim has a binary tree of horizontal/vertical splits. We use a simpler flat model in v1.7:

- Either all horizontal (rows stacked) or all vertical (columns side by side) — but not both at the same time.
- Mix detection: when the user creates a `Ctrl-W v` while the layout is horizontal, refuse (show "E36: Not enough room") OR convert. Pick: we just refuse for v1.7 — keeps Screen rendering simple.
- Equal-share sizing: each window gets `total / count` rows (or columns).

This is a real limitation but cuts the rendering complexity dramatically. Documented prominently. Real nesting comes in a future plan.

Layout state:

```ruby
@split_orientation = nil  # nil | :horizontal | :vertical
```

`@windows` is the ordered list of panes. With orientation `:horizontal`, windows are stacked top-to-bottom. With `:vertical`, side-by-side left-to-right.

### Where Reline's view comes from

When `@current_window` changes, Editor:

1. Saves the outgoing buffer's cursor + scroll to the buffer/window records.
2. Sets `@current_buffer = @current_window.buffer`.
3. Loads `@buffer_of_lines` / `@line_index` / `@byte_pointer` / etc. from `@current_buffer`.
4. Triggers a re-render (the Screen will read updated state).

Reline only ever sees the current buffer through standard ivars. No changes needed in Reline overrides.

### Screen multi-pane rendering

`Screen#render` becomes:

```ruby
def render
  rows, cols = Reline::IOGate.get_screen_size
  @rows, @cols = rows, cols
  layout_windows(@editor.windows, rows - 2, cols)  # reserve 2 for status + prompt
  @editor.windows.each { |w| render_window(w) }
  render_status_line   # global, the bottom 2 rows
  render_bottom_line
  position_cursor       # in the current window
end
```

`layout_windows` divides space evenly. Each window's `(row, col, height, width)` becomes the bounding box for that pane. `render_window` draws:

- Buffer lines (clamped to width, scrolled to scroll_top)
- Selection / search / visual highlights (scoped to that buffer)
- A 1-row dividing line between horizontal splits (status bar per window — vim's behavior)
- A `|` column between vertical splits

For v1.7, each window gets its own status bar at its bottom row showing `[Normal] filename L:C` etc. The current window's status bar gets a slightly different style (e.g., reverse video; non-current is dim).

### File layout (additive)

```
lib/rvim/
  buffer.rb         # NEW — Buffer class
  window.rb         # NEW — Window class
  editor.rb         # @buffers / @windows; swap_to_window; bind Ctrl-W and :b commands
  screen.rb         # multi-pane render; layout_windows; per-window status
  command.rb        # extend :e, :bn, :bp, :b{n,name}, :bd, :sp, :vsp parsers
  marks.rb          # extend get/set for global marks
test/
  test_buffer.rb    # NEW
  test_window.rb    # NEW
  test_editor.rb    # add buffer-switching and window tests
```

## Components

### 1. `Rvim::Buffer`

Holds the per-file state. Constructor optionally reads from disk:

```ruby
class Rvim::Buffer
  def initialize(id, filepath = nil)
    @id = id
    @filepath = filepath
    @lines = filepath && File.exist?(filepath) ? File.readlines(filepath, chomp: true) : ['']
    @lines = [''] if @lines.empty?
    @modified = false
    @marks = Rvim::Marks.new
    @line_index = 0
    @byte_pointer = 0
    @undo_redo_history = [[[''], 0, 0]]
    @undo_redo_index = 0
    @last_visual = nil
  end

  def display_name
    @filepath || '[No Name]'
  end
end
```

### 2. Editor changes

- Replace `Editor#open(path)` with logic that creates-or-finds a Buffer in `@buffers`, then `swap_to_buffer(buffer)`.
- `swap_to_buffer(buffer)`: save current ivars into the outgoing buffer record, load incoming. Handle `current_buffer.nil?` (initial load).
- `:e <path>` execution: route through buffer-creation path. Modified-buffer guard: `:e!` (force).

```ruby
def swap_to_buffer(buffer)
  save_current_to_buffer if @current_buffer
  @current_buffer = buffer
  @buffer_of_lines = buffer.lines
  @line_index = buffer.line_index
  @byte_pointer = buffer.byte_pointer
  @modified = buffer.modified
  @marks = buffer.marks
  @last_visual = buffer.last_visual
  @undo_redo_history = buffer.undo_redo_history
  @undo_redo_index = buffer.undo_redo_index
  @filepath = buffer.filepath
  if @current_window
    @current_window.buffer = buffer
  end
end

private def save_current_to_buffer
  @current_buffer.lines = @buffer_of_lines
  @current_buffer.line_index = @line_index
  @current_buffer.byte_pointer = @byte_pointer
  @current_buffer.modified = @modified
  @current_buffer.marks = @marks
  @current_buffer.last_visual = @last_visual
  @current_buffer.undo_redo_history = @undo_redo_history
  @current_buffer.undo_redo_index = @undo_redo_index
end
```

### 3. Buffer-switching commands

In `Rvim::Command`:

- `:e [path]` — open or switch (path required for new; empty path re-edits current).
- `:e!` — force re-read from disk (discard buffer modifications).
- `:bn[ext]` — switch to next buffer in `@buffer_order`.
- `:bp[rev]` — previous.
- `:b<N>` or `:buffer <N>` — switch to buffer with id N.
- `:b <name>` — switch to buffer whose `display_name` matches.
- `:bd[elete]` — close current buffer; remove from registry; switch to previous (or empty if none).

Modified-buffer guards on `:bd` (vim's `E89`).

### 4. Split commands and bindings

In `Editor#install_key_bindings`, bind `Ctrl-W` (0x17) as a prefix:

```ruby
@config.add_default_key_binding_by_keymap(:vi_command, [0x17], :rvim_window_prefix)
```

`rvim_window_prefix` arms `@waiting_proc` for the next key:

| Key | Action |
|-----|--------|
| `s` / `S` | horizontal split (`:sp`) |
| `v` / `V` | vertical split (`:vsp`) |
| `h` | focus left window |
| `j` | focus below |
| `k` | focus above |
| `l` | focus right |
| `c` | close current window |
| `w` | cycle to next window |

Plus ex commands:

- `:sp[lit] [path]` — horizontal split; optionally open file in new pane
- `:vsp[lit] [path]` — vertical
- `:close` / `:cl` — close current window (alias for `Ctrl-W c`)
- `:on[ly]` — close all other windows (defer? include if cheap)

### 5. Multi-pane Screen rendering

Screen tracks current viewport size and divides among windows. For each window:

```ruby
def render_window(win)
  buffer = win.buffer
  visible_rows = win.height - 1  # last row is per-window status
  adjust_window_scroll(win)
  visible_rows.times do |i|
    idx = win.scroll_top + i
    # ... existing single-pane rendering scoped to win.col, win.col + win.width
  end
  render_window_status(win)
end
```

The current window's status row uses bright reverse video; others use dim. Vertical-split column boundaries get a `│` (or `|`) drawn vertically.

Cursor positioning at end of render uses the current window's offset:

```ruby
abs_row = current_window.row + (current_window.line_index - current_window.scroll_top)
abs_col = current_window.col + current_byte_to_screen_col
move_to(abs_row + 1, abs_col + 1)
```

### 6. Global marks `m{A-Z}`

`Rvim::Marks.set('A', line, col, buffer_id)` extends storage to `Hash<String, [buffer_id, line, col]>` for uppercase. Get returns `[buffer_id, line, col]`. The mark-jump dispatch checks: if uppercase and buffer_id differs, switch buffer first.

```ruby
private def jump_to_mark(name, line_only:)
  pos = @marks.get(name, self)
  return unless pos

  if pos.size == 3  # global mark
    buf_id, line, col = pos
    swap_to_buffer(@buffers[buf_id]) if buf_id != @current_buffer.id
  else
    line, col = pos
  end
  push_jump
  if line_only
    line_text = @buffer_of_lines[line] || ''
    col = first_non_whitespace_col(line_text)
  end
  move_cursor_to(line, col)
end
```

Global marks survive `:bd` (you can jump to a buffer that closes — the buffer reopens from disk).

## Key Technical Decisions

### Why flat splits, not a tree?

A binary tree of splits handles arbitrary nesting (`Ctrl-W s` then `Ctrl-W v` produces a top half + a bottom half that's split into two columns). Implementing the tree adds layout-recompute math, terminal-area subdivision, and a moving "current window" pointer that walks the tree.

For v1.7 we get the *workflow* (split, navigate, close) without the *layout* complexity. A future plan replaces the flat list with a tree once the buffer/window plumbing is solid.

### Cursor on Buffer vs. Window

Vim keeps the cursor per-window, so two windows on the same buffer can show different positions. We put the cursor on the Buffer for v1.7 — simpler and noticeable only when actually splitting the same buffer twice. Document this.

### Modified-buffer guards on switch

`:e new` from a modified buffer: vim warns; rvim will too. `:e!` overrides. `:bd` of a modified buffer: same. `:q` of the last window when any buffer is modified: same.

The wrinkle: with multiple buffers, `:q` can be ambiguous — close current window only? Quit rvim entirely? Match vim: `:q` closes the current window (drops the current buffer from view if no other window holds it). Quit only if it's the last window AND no modified buffers remain.

### What `:e <existing path>` does

If a buffer for that path already exists in the registry, switch to it (preserving its in-memory state). Don't re-read from disk. `:e!` forces a re-read.

### Memory usage

100 open buffers × 100KB each = 10MB of in-memory text. Acceptable. We don't bother swapping to disk for now.

## Verification Plan

### Unit tests

`test/test_buffer.rb`:

- `Buffer.new(1)` creates an empty buffer with `[No Name]`.
- `Buffer.new(1, '/some/path.txt')` reads the file.
- `display_name` returns filepath or `[No Name]`.

`test/test_window.rb`:

- `Window.new(buffer)` defaults scroll_top, line_index, byte_pointer to 0.
- Multiple windows on the same buffer share the cursor (v1.7 simplification).

`test/test_editor.rb` additions:

- `:e foo`, `:e bar`, `:bn` cycles back to foo.
- `:bd` removes current and falls back to previous.
- Buffer marks survive switch and round-trip (`'a` in buf1, switch, switch back, `'a` works).

### PTY end-to-end

1. `:e /tmp/a.txt` then `:e /tmp/b.txt` — both buffers open; `:bp` switches to a.
2. Modify a, `:bn` → b unmodified, `:bp` → a still has changes (`[+]`).
3. `:bd` on a clean buffer drops it; current becomes the previous in order.
4. `:bd` on a modified buffer is blocked with E89.
5. `Ctrl-W s` opens a horizontal split; same buffer in both panes.
6. `Ctrl-W j` moves focus down; `Ctrl-W k` moves up.
7. `:vsp /tmp/c.txt` opens c.txt in a vertical split.
8. `Ctrl-W c` closes current window; the other(s) remain.
9. `mA` in buffer a, switch to b, `'A` returns to a at marked position.
10. `:e` (no arg) on the current buffer is a no-op (same buffer reloaded).

## Stages

1. **`Rvim::Buffer` + `:e` creates new buffer** — extract Buffer class; `:e` finds-or-creates; swap_to_buffer machinery. v1-v1.6 features all still work via the Buffer-mediated path. Verify regression suite.
2. **`:bn` / `:bp` / `:b<N>` / `:b<name>` switch** — cycling and direct lookup.
3. **`:bd` + modified guard** — remove from registry; pick fallback; E89 blocks unsaved.
4. **`Rvim::Window` + single window** — extract Window class; current window points at current buffer; cursor flows through window.
5. **Horizontal splits** — `:sp` / `Ctrl-W s`; flat list of horizontal panes; equal-share sizing.
6. **Multi-pane Screen render** — render each window's region; per-window status row; current-window status highlighted.
7. **Vertical splits** — `:vsp` / `Ctrl-W v`; refuse mixed orientation; column dividers.
8. **`Ctrl-W h/j/k/l/w/c`** — navigation between windows; close current window.
9. **`:q` semantics** — close current window unless last; quit only when last window AND no modified buffers; `:qa!` to force-quit.
10. **Global marks `m{A-Z}` / `'A` / `` `A ``** — extends `Rvim::Marks` and the jump dispatch to switch buffers when needed.
11. **PTY end-to-end** — 10 scenarios; iterate.

Stretch:

- `:close` / `:on[ly]` ex commands.
- Window resize commands.
- Per-window cursor for the same-buffer-twice case.
