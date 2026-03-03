# Rvim v1.1: Visual Mode + Selection Operators — Design Spec

## Context

v1 ships a working editor (motions, operators, file I/O, ex commands, undo/redo, dd/p linewise). The biggest remaining gap is **visual mode** — there's no way to select a region and operate on it. This is the largest single quality-of-life addition we can make and pulls in adjacent polish (indent shifts, motion counts, `gv`) along the way.

This design covers all three visual sub-modes — characterwise (`v`), linewise (`V`), blockwise (`Ctrl-V`) — plus operators that work over a selection (`d`, `c`, `y`, `>`, `<`, `~`).

## Architecture

### Core Idea

Reline has no concept of visual mode — its keymaps are `:emacs`, `:vi_insert`, `:vi_command`. We add visual as a state we track on `Editor` while staying nominally in `vi_command`. When `@visual_mode` is set:

- Motions still come from Reline (`hjkl`, `w`, `b`, `0`, `$`, `gg`, `G`, etc.) and update `@line_index`/`@byte_pointer` as usual.
- Our `update(key)` override intercepts visual-only operators (`v`, `V`, `Ctrl-V`, `d`, `c`, `y`, `>`, `<`, `~`, `o`, `Esc`) and applies them to the range defined by `[anchor, cursor]`.
- Screen renders the selection by inverse-videoing the cells in range during normal render.
- Exiting visual restores normal `vi_command` behavior; the last selection is stashed for `gv`.

This keeps Reline's motion machinery doing the heavy lifting and only adds a small state layer + render hook.

### State on Editor

```ruby
@visual_mode      # nil | :char | :line | :block
@visual_anchor    # [line_index, byte_pointer] when entered
# (cursor end is just @line_index/@byte_pointer)
@last_visual      # { mode:, anchor:, end: } stored on selection finalize for gv
```

Plus the existing clipboard gets a kind tag:

```ruby
@rvim_clipboard          # String for :char/:line, Array<String> for :block
@rvim_clipboard_kind     # :char | :line | :block
```

### File Layout (additive)

```
lib/rvim/
  editor.rb         # adds visual state + intercept logic in update
  screen.rb         # adds inverse-video pass for selection range
  selection.rb      # NEW — Selection value object + range computation
  operations.rb     # NEW — apply-to-range operators (yank, delete, change, shift, tilde)
test/
  test_selection.rb # NEW — range computation across all three modes
  test_operations.rb # NEW — operator behavior on captured ranges
  test_editor.rb    # adds visual-mode entry/exit tests
```

Two new files keep `editor.rb` from ballooning further. `selection.rb` is a pure value object (no Reline coupling); `operations.rb` mutates the editor's buffer through small focused methods.

### Dependencies

No new runtime deps. Test-only: nothing new.

## Components

### 1. `Rvim::Selection`

A value object answering: "given anchor `[al, ac]`, end `[el, ec]`, mode, what cells are in the selection?"

```ruby
class Rvim::Selection
  attr_reader :mode, :start_line, :start_col, :end_line, :end_col

  def self.from(mode, anchor, cursor)
    # Normalize so start is always <= end (top-left for block)
  end

  def includes?(line, col)
    # For Screen rendering — is this cell highlighted?
  end

  def each_segment(buffer_of_lines, &blk)
    # Yields [line_idx, byte_start, byte_end] tuples for use by operators.
  end

  def linewise?
  def charwise?
  def blockwise?
end
```

Normalization rules:
- **Char**: `start = min(anchor, cursor)`, `end = max(...)`. End is *inclusive* of the byte at end_col.
- **Line**: `start.col = 0`, `end.col = bytesize(buffer[end.line])`. Anchor/cursor cols are ignored.
- **Block**: `start = (min line, min col)`, `end = (max line, max col)`. Each row's segment is `[start_col, end_col]`.

### 2. Visual mode entry/exit (Editor)

Bindings on `vi_command`:
- `v` (0x76) → `:rvim_visual_char` — sets `@visual_mode = :char`, `@visual_anchor = [@line_index, @byte_pointer]`
- `V` (0x56) → `:rvim_visual_line`
- `Ctrl-V` (0x16) → `:rvim_visual_block` (also remap from any existing assignment if present)
- Pressing `v`/`V`/`Ctrl-V` *while in visual* switches sub-mode (anchor stays, mode flips)

Exit paths:
- `Esc` (when `@visual_mode`) → clear visual state, snapshot to `@last_visual`
- After any visual operator (`d`/`c`/`y`/`>`/`<`/`~`) → exit to normal automatically (vim behavior)
- `gv` from normal → restore `@last_visual` and re-enter that visual mode

`update(key)` override grows a third branch:

```ruby
def update(key)
  if @command_mode
    process_command_key(key)
  elsif @visual_mode
    process_visual_key(key)   # handles operators, Esc, mode-switch; otherwise falls through to super for motions
  else
    # existing path: status_message reset, before/after diff for @modified, super
  end
end
```

`process_visual_key` looks up the key.char against a small dispatch table; unknown keys fall through to `super` so motions still work. After motion, `@line_index`/`@byte_pointer` is the new selection end.

### 3. Selection rendering (Screen)

`Screen#render` consults `editor.selection` (returns nil or a `Rvim::Selection`). For each visible row, after writing the line, walk the range and emit inverse video for cells that fall inside `selection.includes?(line, col)`.

Implementation: build the line as usual, then before flushing, splice in `\e[7m`/`\e[27m` boundaries at the byte offsets corresponding to selection edges on that line. For `:block`, each visible line in `[start_line..end_line]` gets the same column-range highlighted. For `:line`, full row width gets inverse video (including trailing whitespace pad).

Cursor stays on `@line_index/@byte_pointer` as today — vim shows the cursor at the selection end and the highlight extends inclusively to that cell.

### 4. Operators (`Rvim::Operations`)

One method per operator, all take `(editor, selection)` and mutate the editor's buffer + cursor + clipboard:

| Method | Behavior |
|--------|----------|
| `Operations.yank(editor, sel)` | Copy text into `@rvim_clipboard` with `@rvim_clipboard_kind = sel.mode`. Cursor returns to `sel.start`. |
| `Operations.delete(editor, sel)` | Yank then remove. Buffer collapses; cursor at start. |
| `Operations.change(editor, sel)` | Delete, then `@config.editing_mode = :vi_insert`. |
| `Operations.shift_right(editor, sel, count: 1)` | Prepend `'  '` (or `shiftwidth`) to each line in `[sel.start_line..sel.end_line]`. |
| `Operations.shift_left(editor, sel, count: 1)` | Strip up to `shiftwidth` leading spaces from each line in range. |
| `Operations.toggle_case(editor, sel)` | Flip case for each char in selection range (charwise/blockwise only; linewise treats as full lines). |

Existing `rvim_paste_after`/`rvim_paste_before` extend to read `@rvim_clipboard_kind`:

- `:line` → existing v1 behavior (insert as new line above/below)
- `:char` → splice into current line at cursor (Reline's `vi_paste_next` shape, but driven by our clipboard so visual-mode yank composes)
- `:block` → for each row of the clipboard array, insert that row's text at cursor column on consecutive lines from cursor downward (creating lines if needed)

### 5. Normal-mode `>>` / `<<` (folded polish)

`>` and `<` in `vi_command` arm a `@waiting_proc` (same pattern as `dd`, `gg`, `ZZ`). On a second `>`/`<`, run `Operations.shift_right`/`shift_left` against a synthetic single-line linewise selection at the cursor. Counts work via Reline's `vi_arg` (`3>>` → shift 3 lines).

This isn't strictly visual mode, but it shares all of the indent-shift code, so it lands in the same plan.

### 6. Counts (folded polish)

Reline's `vi_arg` already accumulates digit prefixes (`3j`, `5w`). Our `ed_prev_history`/`ed_next_history` overrides currently honor `arg:` properly (they `arg.times do`). Verify this end-to-end and fix any places where counts are dropped:

- `rvim_g_prefix` (currently ignores arg — `5gg` should still go to line 1, this is fine)
- `vi_to_history_line` (currently ignores arg — `42G` should jump to line 42; today it always goes to last line — **fix this**)
- New visual operators should honor count (`3>` shifts the range 3 levels deep)

### 7. `o` swap + `gv` reselect (Editor)

Inside visual mode:
- `o` (0x6F) → swap `@visual_anchor` with `[@line_index, @byte_pointer]` so the *other* end becomes movable. (Already bound to `rvim_open_below` in normal mode — needs a visual-mode override via `process_visual_key` dispatch.)

In normal mode:
- `gv` → if `@last_visual` is set, restore mode/anchor/end and re-enter visual. Implement as a second branch in `rvim_g_prefix`: if next key is `g` go to top, if next key is `v` reselect. (Need to disambiguate; today it only handles `g`.)

## Key Technical Decisions

### Why a separate state, not a Reline keymap?

Reline's keymaps are static 256-entry arrays. Synthesizing a `:vi_visual` keymap is feasible but expensive: every motion would need to be re-bound on it. Easier to stay in `vi_command` and intercept in `update`. The minor cost is that our `process_visual_key` re-implements a tiny dispatch — but it's ~10 keys, not the whole vi vocabulary.

### Block paste

Block visual + paste is the trickiest case in vim and many editors get it slightly wrong. We adopt the simple semantics: a block-yanked clipboard is `Array<String>` (one per row of the original block). On paste:
- `p` → for each row `i` of the clipboard, insert `clipboard[i]` at `(cursor_line + i, cursor_col + 1)`. Lines past EOF auto-extend.
- `P` → same but at `(cursor_line + i, cursor_col)`.

This matches vim's behavior for the 95% case. Edge cases (pasting a block into a line shorter than `cursor_col`) pad with spaces.

### Highlight rendering performance

Inverse-video splicing happens per-row, per-frame. With 24 rows and a typical selection touching <5 rows, this is negligible. If profiling later shows it's a bottleneck, we can cache the highlighted-line strings keyed on `(line_content, sel_range_for_row)` and reuse across frames.

### What about `vi_change_meta` / `vi_yank` in normal mode?

Reline binds `c` and `y` in `vi_command` already (operator+motion: `cw`, `y$`). Our visual-mode `c`/`y` are *separate* — when `@visual_mode` is set, our intercept fires before Reline's operator dispatch. When not in visual, Reline's existing behavior keeps working. We don't need to touch Reline's operator logic.

## Verification Plan

### Unit tests (test-unit)

- `test_selection.rb`:
  - All three modes: anchor before cursor, anchor after cursor, anchor == cursor.
  - `each_segment` yields correct `[line, byte_start, byte_end]` tuples.
  - `includes?(line, col)` returns true/false at the boundaries.
- `test_operations.rb`:
  - Yank captures the right text and sets the right `@rvim_clipboard_kind`.
  - Delete removes the right range and leaves cursor at start.
  - Change exits to vi_insert.
  - Shift right / shift left touch only lines in range; counts compose.
  - Toggle case flips correctly.
- `test_editor.rb` additions:
  - `v`/`V`/`Ctrl-V` set `@visual_mode` and capture anchor.
  - `Esc` from visual clears state and stashes `@last_visual`.
  - `gv` restores last visual.

### PTY end-to-end (mirror v1's e2e harness)

1. `v`/`y`/`p` round-trips characterwise selection.
2. `V`/`d` deletes selected lines; cursor goes to start.
3. `Ctrl-V`/`d` deletes a rectangle.
4. `>` in linewise visual indents 3 lines by 2 spaces; `<` removes them.
5. `>>` / `<<` work in normal mode with counts (`3>>`).
6. `gv` reselects last selection.
7. `o` in visual swaps anchor.
8. Counts: `3j` moves 3 lines (verify the override honors arg).
9. `42G` jumps to line 42 (folded fix).
10. `~` toggles case across selection.

### Manual smoke test

Open a real Ruby file, select a method body with `V`/motion, indent with `>` a few times, use `gv` after a yank to reselect, verify cursor stays where vim would put it.

## Out of Scope (next plans)

- Search (`/`, `?`, `n`, `N`) — separate plan.
- Macros (`q`, `@`) and `.` repeat — these need a key-recording layer.
- Registers (`"a` etc.) — would replace the single `@rvim_clipboard`.
- Marks (`m`/`'a`).
- Splits / multiple buffers.
- Syntax highlighting.
- vimrc-style configuration.

## Stages

Each ends with a verification step.

1. **Selection foundation** — `Rvim::Selection` value object + tests. No editor wiring yet.
2. **Visual mode state + entry/exit** — `v`/`V`/`Ctrl-V`/`Esc` toggles; status line shows `[Visual]` etc. Selection still inert (no rendering, no operators).
3. **Selection rendering** — Screen highlights selection in inverse video for all three modes.
4. **Yank + paste-by-kind** — `y` from visual, `p`/`P` honor `@rvim_clipboard_kind`. Verify char/line/block round-trips.
5. **Delete + change** — `d`/`c` from visual. `c` exits to insert.
6. **Indent shifts** — visual `>`/`<`, normal `>>`/`<<` with counts.
7. **`o` swap, `gv` reselect, count fixes** — including the `42G` fix on `vi_to_history_line`.
8. **Toggle case (`~`)** — small final operator. Document any v1.1 leftovers in TODO.
9. **PTY end-to-end** — run the 10-scenario harness; iterate until all green.

Stretch (only if time remains in this plan):
- Visual-mode `J` (join selected lines).
- `=` re-indent (probably defer — needs language awareness).
