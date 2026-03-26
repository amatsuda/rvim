# Rvim v1.12: Window Resize + Tab Move + Ftplugin Hooks — Design Spec

## Context

Three loosely-related infrastructure pieces. Each is small on its own; they share the v1.11 window/tab plumbing and a focus on "user-facing knobs we don't have yet."

1. **Window resize** — `Ctrl-W +` / `-` / `>` / `<` / `=`, plus `:resize N` and `:vertical resize N`. Today every window in a layout gets an equal share; users can't grow the active pane.
2. **`:tabmove N`** — reorder tabs. v1.11 tabs are insertion-ordered; users get stuck with whatever order they opened.
3. **Ftplugin hooks** — `Rvim::FileType.register(:ruby) { |buffer, editor| ... }` runs a block whenever a buffer is detected as that filetype. Lets users (or future built-in defaults) auto-set `shiftwidth`, `syntax`, etc. per file type.

Out of scope:

- `:tabdo cmd` (run command in every tab) — defer; easy add later
- Window resize via mouse drag
- Vim's `winheight` / `winwidth` minimum constraints
- `setlocal` triggers from ftplugin (we'll call `editor.settings.set(..., buffer:)` directly)
- `ftdetect` (file content sniffing); we keep extension-based detection

## Architecture

### 1. Window resize

`Rvim::Window` gains `extra_rows` and `extra_cols` integers, default 0. Screen layout gives each window an equal share plus its `extra`:

```ruby
def layout_horizontal(windows, total_rows, total_cols)
  n = windows.size
  per = total_rows / n
  remainder = total_rows - per * n
  row = 0
  windows.each_with_index do |win, i|
    win.row = row
    win.col = 0
    win.height = per + (i < remainder ? 1 : 0) + win.extra_rows
    win.width = total_cols
    row += win.height
  end
  # Clamp so we don't overflow the available rows.
  clamp_window_extents(windows, total_rows, axis: :height)
end
```

`Ctrl-W +`/`-` grows / shrinks `current_window.extra_rows`; the same delta is *subtracted* from the next window's `extra_rows` so total stays the same. `Ctrl-W >`/`<` does the same for `extra_cols`. `Ctrl-W =` resets all extras to 0.

Bindings extend the existing `Ctrl-W` prefix dispatch:

```ruby
when '+'      then resize_current(:height, +1)
when '-'      then resize_current(:height, -1)
when '>'      then resize_current(:width, +1)
when '<'      then resize_current(:width, -1)
when '='      then equalize_windows
```

Ex commands `:resize N`, `:resize +N`, `:resize -N`, `:vertical resize N` set absolute or relative sizes. `:resize 10` means "make the current window 10 rows tall" — implemented by computing the delta from the equal-share baseline and storing in `extra_rows`.

### 2. `:tabmove N`

```ruby
def tab_move(target)
  return if @tabs.size <= 1

  src = @current_tab_index
  dst = target.clamp(0, @tabs.size - 1)
  return if src == dst

  save_current_tab_state
  tab = @tabs.delete_at(src)
  @tabs.insert(dst, tab)
  @current_tab_index = dst
  load_current_tab_state
end
```

Parser: `:tabmove N` (absolute) or `:tabmove +N` / `:tabmove -N` (relative).

### 3. Ftplugin hooks

`Rvim::FileType` is a small registry:

```ruby
module Rvim::FileType
  @hooks = Hash.new { |h, k| h[k] = [] }

  def self.register(filetype, &block)
    @hooks[filetype] << block
  end

  def self.run(filetype, buffer, editor)
    @hooks[filetype].each { |block| block.call(buffer, editor) }
  end
end
```

Editor calls `Rvim::FileType.run(detected_lang, buffer, self)` after buffer creation in `find_or_create_buffer`. The hook can call `editor.settings.set(:shiftwidth, 4, buffer: buffer)` and similar.

Built-in defaults shipped with v1.12:

```ruby
Rvim::FileType.register(:ruby)     { |b, ed| ed.settings.set(:shiftwidth, 2, buffer: b) }
Rvim::FileType.register(:markdown) { |b, ed| ed.settings.set(:shiftwidth, 2, buffer: b) }
Rvim::FileType.register(:json)     { |b, ed| ed.settings.set(:shiftwidth, 2, buffer: b) }
Rvim::FileType.register(:shell)    { |b, ed| ed.settings.set(:shiftwidth, 4, buffer: b) }
```

Users can extend the table from a `~/.rvimrc` or similar in a future plan; for v1.12 the registry is built in.

### File layout (additive)

```
lib/rvim/
  window.rb           # add extra_rows / extra_cols
  editor.rb           # resize_current, equalize_windows, tab_move,
                      # invoke FileType.run on buffer creation
  command.rb          # :resize, :vertical, :tabmove parsers
  screen.rb           # layout uses extras + clamp
  file_type.rb        # NEW — registry
  ftplugins.rb        # NEW — built-in defaults
test/
  test_file_type.rb
```

## Components

### 1. Window resize

`Window` gets two ivars:

```ruby
class Rvim::Window
  attr_accessor :extra_rows, :extra_cols
  # ...
  def initialize(buffer)
    # existing fields
    @extra_rows = 0
    @extra_cols = 0
  end
end
```

Layout reads them; navigation/close zero them when the window count changes (otherwise stale extras would offset balance).

`resize_current(axis, delta)`:

```ruby
def resize_current(axis, delta)
  return if @windows.size < 2

  attr = axis == :height ? :extra_rows : :extra_cols
  cur = @current_window
  idx = @windows.index(cur)
  neighbor = @windows[idx + 1] || @windows[idx - 1]

  cur.send("#{attr}=", cur.send(attr) + delta)
  neighbor.send("#{attr}=", neighbor.send(attr) - delta)
end

def equalize_windows
  @windows.each do |w|
    w.extra_rows = 0
    w.extra_cols = 0
  end
end
```

Ex command `:resize` parses `+N` / `-N` / `N`:

```ruby
def execute_resize(editor, parsed, vertical: false)
  arg = parsed.arg.to_s.strip
  return if arg.empty?

  axis = vertical ? :width : :height
  if arg.start_with?('+', '-')
    delta = arg.to_i
    editor.resize_current(axis, delta)
  else
    target = arg.to_i
    editor.resize_to(axis, target)
  end
end
```

`resize_to(axis, target)` translates an absolute size to an `extra` value:

```ruby
def resize_to(axis, target)
  return if @windows.size < 2

  total = axis == :height ? content_rows_total : @cols
  baseline = total / @windows.size
  extra = target - baseline
  attr = axis == :height ? :extra_rows : :extra_cols
  @current_window.send("#{attr}=", extra)
  # Distribute the negative across other windows
  ...
end
```

### 2. `:tabmove N`

```ruby
def execute_tabmove(editor, parsed)
  arg = parsed.arg.to_s.strip
  return if arg.empty? || editor.tabs.size <= 1

  src = editor.current_tab_index
  dst = if arg.start_with?('+', '-')
          (src + arg.to_i).clamp(0, editor.tabs.size - 1)
        else
          arg.to_i.clamp(0, editor.tabs.size - 1)
        end
  editor.tab_move(dst)
end
```

### 3. Ftplugin hooks

Triggered from `Editor#find_or_create_buffer` after the buffer is built and added to the registry:

```ruby
private def find_or_create_buffer(path)
  existing = @buffers.values.find { |b| b.filepath == path } if path
  return existing if existing

  buf = Rvim::Buffer.new(@next_buffer_id, path, encoding: encoding)
  @next_buffer_id += 1
  @buffers[buf.id] = buf
  @buffer_order << buf.id

  ft = Rvim::Syntax.detect_language(path)
  Rvim::FileType.run(ft, buf, self) if ft

  buf
end
```

The empty-buffer path (`create_empty_buffer`) doesn't invoke the hook since there's no filepath to detect from.

## Key Technical Decisions

### Why store `extra` rather than absolute sizes?

Absolute sizes would need re-balancing logic on every layout (terminal resize, window add/remove). Storing the delta from baseline keeps the math local: when window count changes, extras stay valid; when terminal grows, all windows grow proportionally.

The downside: `:resize 10` doesn't store "10" — it stores `10 - baseline`. If the layout changes (e.g., another split is added), the requested size drifts. Vim has the same problem; users live with it.

### Resize affects only the immediate neighbor

Vim's behavior is more nuanced — it can grow an active window at the expense of multiple neighbors when the immediate one is too small. We start simple: take from / give to the next window in `@windows`. If the neighbor is the last and `@current_window` is the first, take from `@windows[idx + 1]`; if `@current_window` is the last, take from `@windows[idx - 1]`.

### Ftplugin runs once per buffer

The hook fires when a buffer is *created*, not on every render. Subsequent `:set syntax=foo` doesn't re-run the hook — that would be a useful extension but is more state to track.

### `:set` overrides ftplugin

If the user sets `:setlocal sw=8` after the ftplugin set `:setlocal sw=2`, the user's later setting wins (it's a later write to the same overlay key). Same for global `:set sw=N`.

## Verification Plan

### Unit tests

`test/test_file_type.rb`:

- `FileType.register(:lang) { |b, ed| ... }` then `FileType.run(:lang, buf, ed)` invokes the block.
- Multiple registrations on the same lang all run.
- `FileType.run` for an unregistered lang is a no-op.

### PTY end-to-end

1. `Ctrl-W s` then `Ctrl-W +` grows the current window by 1 row; the other shrinks by 1.
2. `Ctrl-W -` reverses.
3. `Ctrl-W =` equalizes back.
4. `:resize 5` sets current window's height to 5.
5. `:vertical resize 30` sets width to 30 in a vertical split.
6. `:tabmove 0` moves the current tab to position 0.
7. `:tabmove +1` shifts the current tab right by one position.
8. `:e foo.rb` (when ftplugin sets `sw=2` for ruby) — `>>` indents by 2.
9. `:e bar.sh` (ftplugin sets `sw=4` for shell) — `>>` indents by 4.
10. User `:set sw=8` after ftplugin — `>>` indents by 8 globally; `:setlocal sw=2` in another buffer doesn't change.

## Stages

1. **Window resize plumbing** — Window.@extra_rows/@extra_cols, Screen layout uses them, equalize_windows resets all. No bindings yet.
2. **`Ctrl-W +/-/</>/=`** — extend Ctrl-W prefix dispatch; resize_current with single-neighbor balancing.
3. **`:resize` / `:vertical resize`** — ex commands.
4. **`:tabmove N`** — parser + executor.
5. **`Rvim::FileType` hook system + built-ins** — registry, run hook from find_or_create_buffer, ship Ruby/Markdown/JSON/Shell shiftwidth defaults.
6. **PTY end-to-end** — 10 scenarios; iterate.

Stretch:

- `:tabdo cmd`.
- `Ctrl-W _` (max height) / `Ctrl-W |` (max width).
- `:windo cmd`.
- ftplugin user-facing registration via `~/.rvimrc`.
