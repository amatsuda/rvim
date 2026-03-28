# Rvim v1.13: Polish Pass — gn/gN + Special Marks + Soft Wrap + Multibyte — Design Spec

## Context

A grab bag of vim-isms deferred from earlier plans. None are big on their own; together they close meaningful gaps in the editor's day-to-day feel. All are independent features so the spec covers four loosely-related pieces.

1. **`gn` / `gN`** — visual-select the next/previous search match. Composes with operators (`cgn` changes next match, dot-repeats turn into find-and-replace).
2. **`'.` `'^` `'[` `']` special marks** — last change position, last insert exit position, start/end of last yanked or changed region.
3. **Soft wrap** — `:set wrap` / `:set nowrap`. Long lines display across multiple rows instead of truncating.
4. **Multibyte cursor accounting** — `truncate` and width math should respect display width, not byte / char count, so CJK (width 2) and ASCII (width 1) round-trip correctly.

Out of scope:

- `gj` / `gk` (display-line navigation) — soft wrap renders correctly but j/k still moves by buffer line. Future plan.
- `:set linebreak` (break at word boundaries) — we wrap mid-word.
- `'(` / `)` (sentence) and `{` / `}` (paragraph) marks — different from `'[` / `']`.
- `gv` extension to "select last gn region" — would be nice; skipping.
- Right-to-left text.

## Architecture

### 1. Soft wrap

Add `wrap` to `Rvim::Settings::DEFAULTS` (default `true`, matching vim). Screen consults `editor.settings.get(:wrap)`. When `true`, a long buffer line spans multiple display rows; when `false`, it truncates at `win.width`.

Render changes:

- For each visible buffer line, split into display segments of width `win.width - gutter_width`.
- Each display segment occupies one row.
- The visible-row counter advances by N for an N-segment line.
- Cursor positioning (row + col) requires translating buffer (line, byte) → (display row, display col): if the buffer line wraps into k segments, find which segment contains the cursor's byte and adjust accordingly.
- Scroll math: `scroll_top` is still a buffer line index, but `adjust_window_scroll` should consider that wrapped lines consume more rows. We approximate by clamping cursor to the visible buffer-line range — soft wrap can show fewer buffer lines than rows.

Simplification for v1.13: `scroll_top` remains buffer-line-indexed. We don't try to scroll *into* a wrapped line (vim does on `Ctrl-Y` / `Ctrl-E` but we'd need display-line scrolling). Cursor on a long line falls within the displayed segments naturally.

### 2. Multibyte cursor

`Screen#truncate(str, width)` currently does `str[0, width]` — char count. For CJK display-width-2 characters, that under-fills the row visually. Replace with a width-aware variant:

```ruby
def truncate_to_width(str, width)
  out = +''
  current = 0
  str.each_char do |c|
    cw = Reline::Unicode.calculate_width(c)
    break if current + cw > width

    out << c
    current += cw
  end
  out
end
```

`display_column(line, byte_pointer)` already uses `Reline::Unicode.calculate_width` correctly — we keep it.

The render path that splices ANSI escapes (selection / search / syntax highlights) must also account for display-width when computing truncate budgets. Audit each splice helper to use width arithmetic instead of char count.

### 3. Special marks

```ruby
@last_change_pos = nil  # [line, col] — last buffer-modifying edit
@last_insert_pos = nil  # [line, col] — last cursor position when leaving insert
@last_yank_range = nil  # { start: [line, col], end: [line, col] }
```

When does each get set?

- `@last_change_pos`: in `update`, after the `super` call returns and `pre_buffer != @buffer_of_lines`, snapshot the cursor.
- `@last_insert_pos`: in `update`, when transitioning from `:vi_insert` → `:vi_command`, snapshot the cursor before super resets.
- `@last_yank_range`: in `set_clipboard` (called from yank/delete/change), capture the editor's cursor at that point as the start; `last_yank_range[:end]` is harder because operators write *after* the operation. Approximation: capture both `[line, col]` (cursor pre-op) and the destination line/col post-op. For the `'[` and `']` use cases (jumping to start/end of last edit), this is good enough.

`Rvim::Marks#get` extends to `'.`, `'^`, `'[`, `']`:

```ruby
def get(name, editor)
  case name
  when "'", '`' then editor.previous_jump_position
  when '<', '>' then editor.visual_position(name)
  when '.'      then editor.last_change_pos
  when '^'      then editor.last_insert_pos
  when '['      then editor.last_yank_range_start
  when ']'      then editor.last_yank_range_end
  when /\A[a-z]\z/ then @table[name]
  when /\A[A-Z]\z/ then editor.global_mark(name)
  end
end
```

Editor exposes the readers that resolve to `[line, col]` or nil.

### 4. `gn` / `gN`

Vim semantics:

- Normal mode `gn`: enter visual mode with the next search match selected (cursor at end of match, anchor at start).
- Normal mode `gN`: same, but previous match.
- Operator-pending `cgn` / `dgn` / `ygn`: equivalent to entering visual mode + selecting + applying the operator.

We implement via the `g`-prefix dispatch (already handles `gg`, `gv`, `gt`/`gT`):

```ruby
private def rvim_g_prefix(key, arg: nil)
  saved_arg = arg
  @waiting_proc = lambda do |key_for_proc, _sym|
    @waiting_proc = nil
    case key_for_proc
    when 'g', 'g'.ord then # ... existing top-of-file
    when 'v', 'v'.ord then reselect_last_visual
    when 't', 't'.ord then tab_advance(saved_arg)
    when 'T', 'T'.ord then tab_retreat(saved_arg)
    when 'n', 'n'.ord then select_next_search_match(:forward)
    when 'N', 'N'.ord then select_next_search_match(:backward)
    end
  end
end

def select_next_search_match(direction)
  return unless @search_pattern && !@search_matches.empty?

  target = Rvim::Search.next_match(@search_matches, @line_index, @byte_pointer, direction)
  return unless target

  line, byte_start, byte_end = target
  @visual_mode = :char
  @visual_anchor = [line, byte_start]
  move_cursor_to(line, byte_end)
end
```

When this runs in operator-pending state (e.g., user typed `c` then `gn`), the visual-mode entry combined with our existing `process_visual_key` flow lets the operator complete via the visual-mode operator branch. *Actually* — operator-pending semantics need verification: `c` sets `@vi_waiting_operator` but our `intercept_visual_key` fires when `@visual_mode` is set. The `cgn` flow becomes:

1. `c` → Reline's `vi_change_meta` sets `@vi_waiting_operator`
2. `g` → falls through to `rvim_g_prefix` (it's bound)
3. `n` (via waiting_proc) → calls `select_next_search_match`, which sets `@visual_mode = :char`
4. Hmm — at this point we're in visual mode AND have an operator pending. Subsequent inputs go through `intercept_visual_key`, but the user has already completed their intent — `gn` was the motion-equivalent.

For v1.13 we'll keep `gn` as "enter visual mode with next match selected." The user can manually finish: `cgn<Esc>` then type the replacement isn't quite vim-compatible, but vanilla `gn` (no operator) works correctly. We document this limitation.

### File layout

```
lib/rvim/
  settings.rb         # DEFAULTS gain :wrap
  screen.rb           # soft-wrap render, truncate_to_width
  editor.rb           # @last_change_pos / @last_insert_pos / @last_yank_range,
                      # gn/gN dispatch
  marks.rb            # extended get for special marks
test/
  test_settings.rb    # :wrap default
  test_screen_wrap.rb # NEW — soft wrap rendering check
```

## Components

### 1. Settings extension

```ruby
DEFAULTS = {
  hlsearch: true,
  shiftwidth: 2,
  number: false,
  relativenumber: false,
  syntax: :auto,
  wrap: true,
}.freeze
```

### 2. Screen wrap logic

`render_window` becomes:

```ruby
def render_window(win)
  buffer = win.buffer
  content_rows = win.height - 1
  is_current = win.equal?(@editor.current_window)
  gw = gutter_width(buffer)
  content_width = win.width - gw
  wrap_on = @editor.settings.get(:wrap)
  cursor_idx = is_current ? @editor.line_index : buffer.line_index

  # Build a list of (buffer_line_idx, segment_text, segment_byte_offset)
  display_rows = []
  scroll = win.scroll_top
  while display_rows.size < content_rows && scroll < buffer.lines.size
    line = render_line(buffer.lines[scroll])
    if wrap_on && line.bytesize > content_width
      offset = 0
      while offset < line.bytesize && display_rows.size < content_rows
        seg = take_display_width(line, offset, content_width)
        display_rows << [scroll, seg, offset]
        offset += seg.bytesize
      end
    else
      display_rows << [scroll, line, 0]
    end
    scroll += 1
  end

  # Pad with tildes
  while display_rows.size < content_rows
    display_rows << [nil, '~', 0]
  end

  # ... render display_rows, status, cursor positioning that maps cursor's
  # buffer (line, byte) to display (row, col) via the segments
end
```

`take_display_width(line, byte_offset, max_width)` returns the longest substring starting at `byte_offset` whose display width fits in `max_width`.

Cursor positioning math: find the display-row in `display_rows` whose `(buffer_line_idx, byte_range)` covers the cursor; the display row index gives the screen row, and `display_column(seg, cursor_byte_pointer - segment_byte_offset)` gives the col.

### 3. Editor: special-mark state

```ruby
attr_reader :last_change_pos, :last_insert_pos
def last_yank_range_start; @last_yank_range&.dig(:start); end
def last_yank_range_end; @last_yank_range&.dig(:end); end

# In update(key), after super:
if @buffer_of_lines != pre_buffer
  @last_change_pos = [@line_index, @byte_pointer]
end

# Detect leaving insert: pre_mode != post_mode
if pre_editing_mode == :vi_insert && current_editing_mode == :vi_command
  @last_insert_pos = [@line_index, @byte_pointer]
end

# In set_clipboard (the operator confirm path):
@last_yank_range = {
  start: [pre_op_line, pre_op_col],
  end: [@line_index, @byte_pointer],
}
```

Capturing `pre_op_line / pre_op_col` requires snapshotting before super in the operator confirm methods. The current `set_clipboard` doesn't have those — we extend `capture_charwise` and the linewise functions to record start positions.

### 4. `gn` / `gN` dispatch

Already sketched in Architecture; the implementation lives in `select_next_search_match`. Tests exercise the visual-mode-entry behavior; operator-pending composition is explicitly out of scope.

## Key Technical Decisions

### Soft-wrap scrolling stays buffer-line-indexed

Vim has `Ctrl-E` / `Ctrl-Y` that scroll by display lines, allowing partial display of a wrapped line at the top of the screen. We keep `scroll_top` buffer-line-indexed: a long line either entirely fits in the visible region or spills past the bottom (where it's clipped). This is simpler and matches `:set scrolloff=0` behavior closely enough.

### `'^` semantics

Vim's `'^` is "the position of the cursor when last leaving insert mode" — which can be different from where insert mode entered. Track on `vi_command_mode` invocation; the cursor at that point is what vim records.

### `'[` and `']` aren't the cursor — they're the modified region

Vim's `'[` is the start of the last edit (where the modification started), `']` is the end. For `iX<Esc>`: `'[` = where 'X' started, `']` = where it ended. For `dw`: `'[` = beginning of deleted region, `']` = the position right after the cursor lands (start of what's now there). We approximate as cursor before / after.

### `take_display_width`

Splitting by display width (not byte or char count) means we never cut a multibyte character mid-byte. Iterate `each_char`, sum widths, stop at the threshold. Returns the substring up to (not including) the char that would overflow.

## Verification Plan

### Unit tests

`test/test_settings.rb` — `:wrap` default is true.

`test/test_screen_wrap.rb`:

- A line shorter than window width occupies one display row.
- A line equal to window width occupies one row.
- A line 2× window width occupies two rows.

`test/test_editor.rb` additions:

- After `iX<Esc>`, `last_change_pos` is set.
- After `iY<Esc>`, `last_insert_pos` is set.
- `'.` and `'^` resolve through Marks#get to those positions.

### PTY end-to-end

1. Open a long line with `:set wrap` (default) — content visible past the column boundary.
2. `:set nowrap` — content truncates.
3. `iXY<Esc>` then `'.` jumps back to the X position.
4. `iA<Esc>kk'^` returns to where insert mode last exited.
5. `yy` then `'[` jumps to start of yanked region.
6. `']` jumps to end of yanked region.
7. `/foo<Enter>gn` selects "foo" visually.
8. Multibyte: line containing `日本語` followed by `xyz` — cursor moves through `xyz` correctly.
9. Multibyte: truncate at window edge doesn't slice a CJK char in half.
10. `gN` from past the last match selects the previous one.

## Stages

1. **`:set wrap` / `:set nowrap` + soft-wrap render** — Settings default; Screen splits long lines into display segments; cursor positioning maps through the segment table.
2. **Multibyte truncate / width-aware splice** — replace `truncate` with `truncate_to_width`; audit every splice helper to use display width.
3. **`'.` last change** — `@last_change_pos` set in update; Marks#get extended.
4. **`'^` last insert** — track on insert→normal transition.
5. **`'[` / `']` last yank/change range** — capture in operator confirm paths.
6. **`gn` / `gN` visual-select last match** — extend `rvim_g_prefix` dispatch.
7. **PTY end-to-end** — 10 scenarios; iterate.

Stretch:

- `gj` / `gk` display-line navigation.
- `:set linebreak` (word-aware wrap).
- `'(` `)` `{` `}` sentence/paragraph marks.
- `cgn` / `dgn` operator-pending composition with full vim fidelity.
