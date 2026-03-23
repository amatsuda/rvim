# Rvim v1.10: Listing UIs (:ls, :marks, :jumps, :registers) — Design Spec

## Context

Several previous plans deferred their "list-it" commands because we lacked a framework for showing multi-line output below the editor. v1.10 builds that framework and ships four commands that need it:

- **`:ls` / `:buffers`** — open buffers, with id / modified flag / filename
- **`:marks`** — local marks (a-z) and global marks (A-Z), with line/col/file
- **`:jumps`** — jump list with current position arrow, line/col, line text preview
- **`:registers` / `:reg`** — populated registers (`""`, `"0`-`"9`, `"a`-`"z`, `"+`, `"%`) with content preview

All share the same UI shape: a multi-row overlay at the bottom of the screen, page-by-page advance with `Space`/`Enter`/`<CR>`, `q`/`Esc` to dismiss. Matches vim.

Out of scope:

- Interactive selection from the list (vim's listing commands don't support this either; user reads, then types `:b 3` etc.)
- `:history` (we don't track command history yet)
- Argument-filtered listings (`:reg a` for just register a)
- Search through list contents

## Architecture

### `Rvim::ListView`

```ruby
class Rvim::ListView
  attr_reader :lines, :cursor

  def initialize(lines)
    @lines = lines  # Array<String> (already formatted)
    @cursor = 0     # index into @lines, points at the first line of the current page
  end

  def page_size(rows)
    [rows - 1, 1].max  # last row is the "-- More --" prompt
  end

  def page(rows)
    @lines[@cursor, page_size(rows)]
  end

  def more?(rows)
    @cursor + page_size(rows) < @lines.size
  end

  def advance!(rows)
    @cursor += page_size(rows)
  end
end
```

### Editor list-mode

When a listing command runs:

1. Build the formatted lines.
2. Set `@list_view = Rvim::ListView.new(lines)` and `@prompt_mode = :listing`.
3. Render takes over the bottom N rows (from below the current window status to above the cmdline) to draw `@list_view.page(N)`.
4. Bottom row shows `-- More --` (when more exists) or `Press ENTER or type command to continue` (vim's text).
5. `update(key)` while `prompt_mode == :listing`:
   - `Space` / `f` / `Ctrl-F` / `<CR>` → `advance!`; if no more, dismiss.
   - `q` / `Esc` / `Ctrl-C` → dismiss.
   - Any other key while no more — dismiss and re-dispatch the key (matches vim, where typing `:b 3` from the prompt switches to the buffer).

Number of rows the overlay uses: chosen at command-time to fit the list, capped at `@rows / 2` so the editor area stays visible.

### Format helpers

Each command has a `format_*` method that returns `Array<String>`:

```ruby
def self.format_buffers(editor)
  header = '  N  flags  Name'
  rows = editor.buffer_order.map do |id|
    b = editor.buffers[id]
    cur = (id == editor.current_buffer&.id) ? '%' : ' '
    mod = b.modified ? '+' : ' '
    "#{cur} #{id}  #{mod}     #{b.display_name}"
  end
  [header, *rows]
end
```

`:marks`, `:jumps`, `:registers` follow the same shape: header + body rows.

### File layout (additive)

```
lib/rvim/
  list_view.rb       # NEW — Rvim::ListView
  command.rb         # add :ls, :buffers, :marks, :jumps, :registers, :reg
  editor.rb          # @list_view, @prompt_mode = :listing branch in update
  screen.rb          # render list overlay
test/
  test_list_view.rb
```

## Components

### 1. `Rvim::ListView`

Pure-data container with paging math. No editor coupling.

### 2. `:ls` / `:buffers` formatter

```
  N  flags  Name
% 1  +     /tmp/a.txt
  2        /tmp/b.txt
  3        [No Name]
```

Header line + per-buffer line. `%` marks current; `+` marks modified. Followed by id, name.

### 3. `:marks` formatter

```
mark  line  col  file/text
'a       3    0  hello world
'b       7   10  beta line text
'A       1    0  /tmp/global.txt
```

For local marks, show the line text from the current buffer. For global marks, show the filepath.

### 4. `:jumps` formatter

```
 jump line  col  file/text
   3   12    0  function foo
   2    7   10  beta line text
>  1    1    0  alpha (current)
```

Newest at top (vim convention reversed), `>` arrow at the current `@jump_index`.

### 5. `:registers` formatter

```
type  name  content
   c   ""   hello world
   l   "0   line of text\n
   c   "a   register a content
   l   "1   recently deleted\n
```

`type` is `c`/`l`/`b` (char/line/block). Truncate content at 60 chars. Show literal `\n` for embedded newlines.

### 6. Editor integration

```ruby
def show_list(lines)
  @list_view = Rvim::ListView.new(lines)
  @prompt_mode = :listing
end

private def process_listing_key(key)
  ch = key.char
  case ch
  when ' ', "\r", "\n", 'f', "\x06" # advance
    if @list_view.more?(list_rows)
      @list_view.advance!(list_rows)
    else
      dismiss_list
    end
  when 'q', "\e", "\x03"
    dismiss_list
  else
    dismiss_list
    update(key) # re-dispatch (matches vim's "anything else continues normal mode")
  end
end

def dismiss_list
  @list_view = nil
  @prompt_mode = nil
end

def list_rows
  return 0 unless @screen

  [(@screen.rows / 2).to_i, 4].max
end
```

`update` branches: when `@prompt_mode == :listing`, route to `process_listing_key`.

### 7. Screen render

In render, when `@editor.prompt_mode == :listing`:

- Reduce window content area to leave room for the overlay (last `list_rows + 1` rows of `@rows`).
- Draw a separator row (or just background) above the overlay.
- Draw `@list_view.page(list_rows - 1)` lines at rows `[@rows - list_rows..@rows - 2]`.
- Bottom row (`@rows`) shows `-- More --` when `@list_view.more?` else `Press ENTER or type command to continue`.

Cursor position: hide cursor while in listing mode (or position it at the bottom prompt).

## Key Technical Decisions

### Why per-page paging and not a scrollable widget?

Vim's classic `-- More --` paging is well-understood and trivial to implement. A scrollable widget with `j`/`k` navigation would be nicer but multiplies UI state. We can iterate.

### Re-dispatching unknown keys

Vim's "Press ENTER or type command" prompt accepts any key — the typed key dismisses the prompt and goes to normal mode. So pressing `:b 3` while in listing mode dismisses the list, opens the `:` prompt with `b 3` already typed, and Enter switches to buffer 3.

We re-dispatch by calling `update(key)` after `dismiss_list`. The first key may need to be `:` to start the prompt; that works through this path.

### Why a separate `@prompt_mode = :listing`?

Putting it under the existing prompt-mode dispatch keeps the input pipeline single-shape. The bottom 1 row stays the prompt area conceptually; we just expand it upward for the duration of the list.

### Empty registers

When a register has no content (most named registers will be unset), don't list them. Only show populated entries.

## Verification Plan

### Unit tests

`test/test_list_view.rb`:

- `ListView.new(['a','b','c','d']).page(3)` returns first 2 + the prompt slot accounting.
- `more?` true when more lines remain past first page; false on last page.
- `advance!` moves the cursor.

### PTY end-to-end

1. `:ls` shows buffer list including current marker `%`.
2. `:ls` after `:e foo`/`:e bar` shows two buffers.
3. `:marks` after `ma` shows mark `a` with the current line.
4. `:marks` shows global marks (uppercase) with filepath.
5. `:jumps` after some search/G/`:N` activity shows the jump list.
6. `:registers` after `yy` shows `""` and `"0` with the yanked content.
7. List paging: with 30 buffers, `Space` advances the page.
8. `q` dismisses without consuming further keys.
9. Pressing an unknown key dismisses and re-dispatches.
10. List screen reserves cursor at the prompt during display.

## Stages

1. **`Rvim::ListView` foundation** — class, paging math, unit tests.
2. **`:ls` / `:buffers`** — formatter, command parser/executor, list-mode dispatch in update, Screen render.
3. **`:marks`** — formatter (local + global) using existing Marks/GlobalMarks.
4. **`:jumps`** — formatter walking the jump list with `>` arrow.
5. **`:registers` / `:reg`** — formatter walking populated registers.
6. **PTY end-to-end** — 10 scenarios; iterate.

Stretch:

- Interactive `j`/`k`/`Enter` to select-and-jump from the list.
- `:reg a` to filter to just register a.
- `:filter /pat/ :ls` (vim's filter wrapper).
