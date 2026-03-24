# Rvim v1.11: Tab Pages — Design Spec

## Context

v1.7 gave us multiple buffers and window splits within a single layout. The next step up the hierarchy is **tab pages** — top-level containers, each holding its own collection of windows. `:tabnew` opens a fresh tab, `gt` / `gT` cycle, `:tabclose` removes the current. Each tab keeps its own split orientation, focused window, and view of the buffer registry (which is shared across all tabs).

This plan covers:

- `:tabnew [path]` — open a new tab, optionally with a file
- `gt` / `gT` (and `:tabnext` / `:tabprev`) — cycle tabs
- `Ngt` — jump to the Nth tab
- `:tabclose` / `:tabc` — close the current tab (refuse to close the last one)
- `:tabonly` / `:tabo` — keep only the current tab
- A tabline at the top of the screen showing all tab names with the current one highlighted

Out of scope (deferred):

- `:tabmove N` (reorder tabs)
- `:tabdo cmd` (run command in every tab)
- Mouse interaction with the tabline
- Tab-specific settings (vim's `tabprev` / `tabpagenr` etc.)
- `Ctrl-W T` (move current window to a new tab)

## Architecture

### `Rvim::Tab`

A Tab owns the per-tab window state. Buffers stay global on the Editor.

```ruby
class Rvim::Tab
  attr_accessor :windows, :current_window, :split_orientation

  def initialize(window)
    @windows = [window]
    @current_window = window
    @split_orientation = nil
  end

  def display_name(editor)
    win = @current_window
    return '[New]' unless win

    name = win.buffer&.display_name || '[No Name]'
    File.basename(name)
  end
end
```

### Editor: tab registry

```ruby
@tabs = []                # Array<Tab>
@current_tab_index = 0
```

`@windows`, `@current_window`, `@split_orientation` become *aliases* mirroring the current tab's fields. Whenever we switch tabs:

1. Save the outgoing tab's `windows` / `current_window` / `split_orientation` from Editor's ivars.
2. Set `@current_tab_index = target`.
3. Load the new tab's fields back onto Editor.
4. Activate the new tab's current window (which routes through `swap_to_buffer`).

```ruby
def swap_to_tab(idx)
  return if idx < 0 || idx >= @tabs.size

  save_current_tab_state
  @current_tab_index = idx
  load_current_tab_state
end

private def save_current_tab_state
  tab = @tabs[@current_tab_index]
  return unless tab

  tab.windows = @windows
  tab.current_window = @current_window
  tab.split_orientation = @split_orientation
end

private def load_current_tab_state
  tab = @tabs[@current_tab_index]
  @windows = tab.windows
  @current_window = tab.current_window
  @split_orientation = tab.split_orientation
  activate_window(@current_window) if @current_window
end
```

### Tabline rendering

When `@tabs.size > 1`, Screen reserves the top row for the tabline:

```
| 1: a.txt | 2: b.json *| 3: README.md |
```

The current tab gets reverse-video; others are dim. Window content shifts down by one row.

When only one tab exists, no tabline (vim default — `showtabline=1`).

### File layout (additive)

```
lib/rvim/
  tab.rb         # NEW — Rvim::Tab
  editor.rb      # @tabs, swap_to_tab, ensure_current_tab on init,
                 # bind gt / gT, :tabnew / :tabclose / :tabonly
  command.rb     # :tabnew, :tabnext, :tabprev, :tabclose, :tabonly parsers
  screen.rb      # tabline render; shrink window area when present
test/
  test_tab.rb
```

## Components

### 1. Ensure-current-tab on initialization

In `Editor#initialize` (or just before render starts), if `@tabs` is empty, create one:

```ruby
private def ensure_current_tab
  return unless @tabs.empty?

  win = @windows.first || Rvim::Window.new(@current_buffer)
  @windows = [win]
  @current_window = win
  @tabs << Rvim::Tab.new(win)
  @current_tab_index = 0
end
```

Called from `swap_to_buffer`'s `ensure_current_window` path so we never have the editor in a state with windows but no tabs.

### 2. `gt` / `gT` bindings

```ruby
@config.add_default_key_binding_by_keymap(:vi_command, [?g.ord, ?t.ord], :rvim_tab_next)
```

Hmm — Reline's default key bindings are single-byte indexed by ASCII code, not multi-byte sequences. `gt` is two keystrokes — we already use `g`-prefix dispatch via `rvim_g_prefix`. Add `t` and `T` to that dispatcher's case branch.

```ruby
private def rvim_g_prefix(key)
  @waiting_proc = lambda do |key_for_proc, _sym|
    @waiting_proc = nil
    case key_for_proc
    when 'g', 'g'.ord then @line_index = 0; @byte_pointer = 0
    when 'v', 'v'.ord then reselect_last_visual
    when 't', 't'.ord then tab_next
    when 'T', 'T'.ord then tab_prev
    end
  end
end

def tab_next(arg: 1)
  return if @tabs.size < 2
  swap_to_tab((@current_tab_index + arg) % @tabs.size)
end

def tab_prev(arg: 1)
  return if @tabs.size < 2
  swap_to_tab((@current_tab_index - arg) % @tabs.size)
end
```

Counts (`5gt` jumps to tab 5): the `arg` from `vi_arg` propagates. For `Ngt` going to the *N*th tab (vim's behavior, not "advance N"), check arg explicitly:

```ruby
def tab_next(arg: nil)
  return if @tabs.size < 2

  target = if arg && arg > 0
             (arg - 1).clamp(0, @tabs.size - 1)
           else
             (@current_tab_index + 1) % @tabs.size
           end
  swap_to_tab(target)
end
```

### 3. `:tabnew [path]`

```ruby
when 'tabnew', 'tabe', 'tabedit' then :tabnew
```

```ruby
when :tabnew
  editor.tab_new(parsed.arg)
```

Editor side:

```ruby
def tab_new(path = nil)
  buf = path && !path.empty? ? find_or_create_buffer(path) : empty_buffer
  win = Rvim::Window.new(buf)
  tab = Rvim::Tab.new(win)
  save_current_tab_state
  @tabs.insert(@current_tab_index + 1, tab)
  @current_tab_index += 1
  @windows = tab.windows
  @current_window = win
  @split_orientation = nil
  activate_window(win)
end

private def empty_buffer
  buf = Rvim::Buffer.new(@next_buffer_id, nil, encoding: encoding)
  @next_buffer_id += 1
  @buffers[buf.id] = buf
  @buffer_order << buf.id
  buf
end
```

### 4. `:tabclose` / `:tabonly`

```ruby
def tab_close
  return if @tabs.size <= 1

  save_current_tab_state
  @tabs.delete_at(@current_tab_index)
  @current_tab_index = [@current_tab_index, @tabs.size - 1].min
  load_current_tab_state
end

def tab_only
  return if @tabs.size <= 1

  save_current_tab_state
  current = @tabs[@current_tab_index]
  @tabs = [current]
  @current_tab_index = 0
  load_current_tab_state
end
```

### 5. Tabline render

In `Screen#render`, before laying out windows:

```ruby
def render_tabline
  return '' if @editor.tabs.size <= 1

  parts = @editor.tabs.each_with_index.map do |tab, i|
    name = tab.display_name(@editor)
    label = " #{i + 1}: #{name} "
    if i == @editor.current_tab_index
      "#{REVERSE_ON}#{label}#{REVERSE_OFF}"
    else
      label
    end
  end
  tabline = parts.join('|')
  move_to(1, 1) + ERASE_LINE + truncate(tabline, @cols).ljust(@cols)
end
```

Shift window layout down by one row when tabline is shown:

```ruby
def render
  @rows, @cols = Reline::IOGate.get_screen_size
  reserved_top = @editor.tabs.size > 1 ? 1 : 0
  reserved = @editor.prompt_mode == :listing ? list_overlay_rows + 1 : 1
  layout_windows(@rows - reserved - reserved_top, @cols)
  # Apply offset:
  @editor.windows.each { |w| w.row += reserved_top } if reserved_top.positive?

  out = +HIDE_CURSOR
  out << render_tabline if reserved_top.positive?
  @editor.windows.each { |w| out << render_window(w) }
  ...
```

The cursor positioning at the end also accounts for `reserved_top`.

## Key Technical Decisions

### Why mirror, not delegate?

Editor.@windows is read by *many* places (Operations, Screen, listing formatters). Adding a layer of indirection through `editor.current_tab.windows` would touch a lot of code. Instead, the live `@windows`/`@current_window`/`@split_orientation` ivars on Editor are the canonical "view" of the current tab, and `swap_to_tab` syncs them in/out atomically.

### Buffer registry stays global

Tabs share buffers. Switching to a new tab doesn't fork the buffer list — that would conflict with vim's universal `:ls`/`:b` behavior and surprise users. A buffer can appear in zero, one, or many tabs simultaneously.

### One-window-per-tab on creation

`:tabnew` creates a tab with exactly one window showing one buffer. The user can then `:sp` / `:vsp` within the tab to add more.

### `:q` from the only window in a tab

If `:q` runs in a tab with only one window:

- If `@tabs.size > 1`: close the tab (same as `:tabclose`).
- Else: existing single-window quit logic (modified guard, exit editor).

This matches vim. Implementation: `execute_quit` checks `@tabs.size > 1 && @windows.size == 1`.

### Tabline placement

Top row, single line. Vim has `:set showtabline={0,1,2}`; we hardcode the equivalent of `1` (only show when 2+ tabs exist). Adding the setting is one line if requested.

### `gt` arg semantics

Vim's `Ngt`: with N omitted, advance one tab; with N given, jump to the Nth tab. We mirror.

## Verification Plan

### Unit tests

`test/test_tab.rb`:

- `Tab.new(window)` initializes with a single-window list.
- `display_name` returns the basename of the current window's buffer filepath, or `[No Name]`.

### PTY end-to-end

1. `:tabnew /tmp/b.txt` after opening `/tmp/a.txt` shows tabline with two entries.
2. `gt` from tab 1 switches to tab 2.
3. `gT` from tab 2 switches back to tab 1.
4. `2gt` jumps to tab 2.
5. `:tabclose` removes current tab; falls back to neighbor.
6. `:tabclose` on the only tab is a no-op (or status message).
7. `:tabonly` from 3-tab setup leaves just the current.
8. Each tab keeps its own window split independent of others.
9. Tabline shows current tab in reverse video, others dim.
10. Switching tabs preserves cursor position in each.

## Stages

1. **`Rvim::Tab` foundation + ensure_current_tab** — class, automatic creation on init, save/load tab state. Verify v1-v1.10 still work.
2. **`gt` / `gT` + `:tabnext` / `:tabprev`** — bindings via rvim_g_prefix dispatch, ex commands.
3. **`:tabnew [path]`** — create-and-switch.
4. **`:tabclose` + `:tabonly`** — remove tabs.
5. **Tabline render** — Screen draws tabs at the top when more than one.
6. **`:q` close-tab semantics** — when last window in tab, close the tab.
7. **PTY end-to-end** — 10 scenarios; iterate.

Stretch:

- `:tabmove N`.
- `:tabdo cmd` (apply command to every tab).
- Mouse-clickable tabline.
- Tab-page-local options (vim's `set` vs `setlocal` analog at tab scope).
