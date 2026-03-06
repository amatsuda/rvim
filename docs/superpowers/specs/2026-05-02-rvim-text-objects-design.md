# Rvim v1.2: Text Objects + Operator+Motion Fix — Design Spec

## Context

v1.1 added visual mode and selection-based operators. The next layer is **text objects** — `iw`, `i"`, `i(`, `ap` and friends — which compose with the operators we already have (`d`, `c`, `y`) to unlock vim's most powerful editing patterns: `diw` (delete a word), `ci(` (change inside parens), `yap` (yank a paragraph).

Folded in: a latent bug from v1. `rvim_d_prefix` was added to make `dd` work but it swallows the second key, which means **`dw`, `d$`, `cw`, `yw`, `cb`, `c$`, etc. all silently do nothing**. The text-object plan needs to refactor operator handling regardless, so we fix this on the way through.

## Architecture

### The two problems

1. **dd vs dw collision.** In vim, the first `d` is an operator, then the next input decides what gets deleted: another `d` (linewise current line), a motion (`dw`, `d$`), or a text object (`diw`). v1 bound `d` to `rvim_d_prefix` which only handles the `dd` case — Reline's `vi_delete_meta_confirm` path that handles `dw` never runs because we shadowed `d`.
2. **Text objects are not motions.** A motion like `w` produces a single endpoint; the operator deletes from cursor to that endpoint. A text object like `iw` produces a *range* (start AND end), independent of cursor position. Reline's operator+motion machinery doesn't model this.

### The fix

Stop binding `d`, `c`, `y` to our own prefix methods. Let Reline's existing operator dispatch own the keystroke flow:

- First `d` calls Reline's `vi_delete_meta`, which sets `@vi_waiting_operator = :vi_delete_meta_confirm`.
- Second key dispatches normally:
  - `d` again → Reline's existing dd shortcut (currently just empties the line; we need to extend it).
  - A motion (`w`, `$`, `b`...) → Reline runs the motion, computes `byte_pointer_diff`, calls `vi_delete_meta_confirm(byte_pointer_diff)`.
  - `i` or `a` → **we intercept** in `update`, since these are normally insert-mode keys but become text-object prefixes during operator-pending.

We override only what we need to bend Reline's behavior:

| Method | Why we override |
|--------|-----------------|
| `vi_delete_meta_confirm(byte_pointer_diff)` | Capture cut text into `@rvim_clipboard` with `:char` kind so paste round-trips. |
| `vi_delete_meta(key, arg:)` | Intercept the `dd` linewise shortcut: capture full line(s) to clipboard with `:line` kind. |
| `vi_yank_confirm` / `vi_yank` | Same for yank. |
| `vi_change_meta_confirm` / `vi_change_meta` | Same for change. |
| `update(key)` | Add the text-object intercept before super when `@vi_waiting_operator` is set and key is `i`/`a`. |

### Text-object dispatch

When the user is in operator-pending (`@vi_waiting_operator` set) and presses `i` or `a`, we set `@waiting_proc` to consume the next key as the object identifier:

```ruby
def update(key)
  if operator_pending? && (key.char == 'i' || key.char == 'a')
    inclusive = key.char == 'a'
    @waiting_proc = lambda do |obj_key, _sym|
      @waiting_proc = nil
      range = TextObject.find(obj_key, self, inclusive: inclusive)
      apply_pending_operator(range) if range
    end
    return
  end
  # ... existing branches
end
```

`apply_pending_operator(range)` reads `@vi_waiting_operator` (`:vi_delete_meta_confirm`, `:vi_change_meta_confirm`, `:vi_yank_confirm`), turns the range into a `Rvim::Selection`, and routes to `Operations.delete` / `change` / `yank` — the same pipeline visual mode uses. This is why text objects are cheap: all the heavy lifting (clipboard tagging, line collapse on multi-line delete, change-and-insert) is already implemented.

### File layout (additive)

```
lib/rvim/
  text_object.rb    # NEW — TextObject.find(key, editor, inclusive:) returns a Selection or nil
  editor.rb         # operator-pending intercept, drop rvim_d_prefix binding,
                    # override vi_delete_meta and confirm methods
  operations.rb     # no change (text objects produce Selections, then existing ops apply)
test/
  test_text_object.rb # NEW — boundary detection per object type
  test_editor.rb      # operator+motion regression coverage (dw, d$, cw, yw)
```

`text_object.rb` is the bulk of new logic. Each object family is one method; `find` is a small dispatch:

```ruby
module Rvim::TextObject
  def self.find(key, editor, inclusive:)
    case key
    when 'w' then word(editor, inclusive: inclusive, big: false)
    when 'W' then word(editor, inclusive: inclusive, big: true)
    when '"', "'", '`' then quote(editor, key, inclusive: inclusive)
    when '(', ')', 'b' then bracket(editor, '(', ')', inclusive: inclusive)
    when '[', ']' then bracket(editor, '[', ']', inclusive: inclusive)
    when '{', '}', 'B' then bracket(editor, '{', '}', inclusive: inclusive)
    when '<', '>' then bracket(editor, '<', '>', inclusive: inclusive)
    when 'p' then paragraph(editor, inclusive: inclusive)
    end
  end
end
```

## Components

### 1. Operator-pending intercept (Editor)

Add a tiny predicate `operator_pending?` that returns `@vi_waiting_operator != nil`. In `update`, before the existing branches, check for the text-object prefix:

```ruby
def update(key)
  if @command_mode
    process_command_key(key)
  elsif @visual_mode
    return if intercept_visual_key(key)
    super_with_modified_diff(key)
  elsif operator_pending? && text_object_prefix?(key)
    enter_text_object_pending(key.char == 'a')
  else
    super_with_modified_diff(key)
  end
end
```

`text_object_prefix?(key)` returns true only when char is `'i'` or `'a'`. Without operator-pending, `i` and `a` keep their normal-mode meanings (vi_insert / vi_add) — no behavior change there.

### 2. Clipboard-aware operator confirms (Editor)

Override the three `*_confirm` methods Reline calls after a motion runs. Each captures the cut/yanked text into our kind-tagged clipboard before delegating to super:

```ruby
private def vi_delete_meta_confirm(byte_pointer_diff)
  return if byte_pointer_diff.zero?

  start_line, start_col, end_line, end_col = byte_range_to_coords(byte_pointer_diff)
  sel = Selection.from(:char, [start_line, start_col], [end_line, end_col], @buffer_of_lines)
  cut = Operations.extract_char(@buffer_of_lines, sel)
  set_clipboard(cut, :char)
  super
end
```

`vi_yank_confirm` and `vi_change_meta_confirm` mirror this. The shape is consistent: capture before super, super does the actual mutation.

For the `dd`/`cc`/`yy` linewise shortcuts, override the operator method itself:

```ruby
private def vi_delete_meta(key, arg: nil)
  if @vi_waiting_operator == :vi_delete_meta_confirm && arg.nil?
    count = @vi_waiting_operator_arg || 1
    delete_lines_linewise(count)
    @vi_waiting_operator = nil
    @vi_waiting_operator_arg = nil
    return
  end
  super
end
```

This replaces the v1 `rvim_d_prefix` path entirely. **Drop the `:vi_command, [?d.ord], :rvim_d_prefix` binding** so Reline's natural dispatch reaches `vi_delete_meta`.

### 3. Word text objects (`iw` / `aw` / `iW` / `aW`)

`Rvim::TextObject.word(editor, inclusive:, big:)`:

- Word boundary: `big = false` → `\w` (alphanumeric + underscore) plus separators that flip class. `big = true` → whitespace as the only separator.
- Algorithm: starting at cursor, scan left for the start of the current "thing" and right for the end. If `inclusive` (the `a` flavor), also include trailing whitespace (or leading if no trailing exists at EOL).
- Returns a `Rvim::Selection` with `:char` mode (always single-line for word objects).
- Edge cases: cursor on whitespace → `iw` selects the whitespace run, not the next word (vim behavior).

### 4. Quote text objects (`i"` / `a"` / `i'` / `a'` / `` i` `` / `` a` ``)

`Rvim::TextObject.quote(editor, char, inclusive:)`:

- Single-line only (vim's quote text objects don't span newlines).
- Find the nearest enclosing pair on the cursor's line: scan left for an unescaped `char`, scan right for the next.
- If cursor is on a quote, treat it as the *closing* quote (consistent with vim) and look right for the next opening one to start a fresh pair.
- Inclusive includes the quotes plus one adjacent space if present.
- No nesting; quote pairs are flat.

### 5. Bracket text objects (`i(` / `a(` / `i[` / `a[` / `i{` / `a{` / `i<` / `a<`)

`Rvim::TextObject.bracket(editor, open_ch, close_ch, inclusive:)`:

- Multi-line capable.
- Walk left from cursor counting nesting (open decrements, close increments) until we find the unmatched opening bracket. Then walk right from that position counting nesting until we find the matching close.
- Skip brackets inside strings? **No** — vim doesn't, and adding it bloats this. Cursor-on-bracket case: `(` treated as the opening bracket of the inner pair, `)` as closing.
- `b` is an alias for `(`, `B` for `{` (vim convention).

### 6. Paragraph text objects (`ip` / `ap`)

`Rvim::TextObject.paragraph(editor, inclusive:)`:

- Paragraph = consecutive non-blank lines.
- Inclusive (`ap`) includes the trailing blank-line block (or leading if at EOF).
- Always linewise mode — return a `Rvim::Selection` with `:line`.

### 7. Visual mode extensions

Visual + text object: `vit`, `daw`, `vap`. Same `TextObject.find` call, but instead of running an operator, replace the visual selection. Implementation: in `intercept_visual_key`, when `i` or `a` is pressed, arm a `@waiting_proc` that computes the text object and updates `@line_index/@byte_pointer/@visual_anchor` to span the result.

```ruby
when 'i', 'a'
  inclusive = (ch == 'a')
  @waiting_proc = lambda do |obj_key, _sym|
    @waiting_proc = nil
    range = TextObject.find(obj_key, self, inclusive: inclusive)
    if range
      @visual_anchor = [range.start_line, range.start_col]
      move_cursor_to(range.end_line, range.end_col)
      @visual_mode = range.linewise? ? :line : :char
    end
  end
  return true
```

This means visual mode's `i`/`a` *don't* fall through to motions — they always start a text-object prefix. That matches vim.

## Key Technical Decisions

### Why not implement text objects as Reline motions?

A motion in Reline produces an endpoint; the operator deletes from cursor to endpoint. Text objects produce a *range* whose start may be **before** the cursor. Forcing them into the motion shape would require pre-positioning the cursor at the start, which mutates editor state in ways Reline's machinery doesn't expect. Treating them as a parallel dispatch in `update` is cleaner.

### Why override `*_confirm` instead of just calling super and inspecting the buffer?

Reline's operator path mutates the buffer in `*_confirm` — by the time super returns, the cut text is gone. Capturing it pre-super gives us the right state without re-deriving it from a diff.

### Counts

`2diw` (delete two inner words) and `d2w` (delete forward 2 words) both need to work.

- `d2w`: Reline's `vi_arg` already accumulates the digit count and forwards it to motions. The motion's `byte_pointer_diff` is computed correctly. `vi_delete_meta_confirm` gets a larger diff. **No new code.**
- `2diw`: `vi_arg` is 2 when `d` fires; we propagate `@vi_waiting_operator_arg = arg`. When the text object lands, we apply `count` iterations of "extend the range by one more word." For non-word objects (quotes, brackets), counts are ignored — vim does the same.

### Boundary edge cases

The hardest part of text objects is boundary detection. Specific cases the design must handle:

- Cursor on whitespace, `iw` → select the whitespace run.
- Cursor at EOL, `iw` → select the last word on the line.
- Empty line, `ip` → select the blank-line block.
- Quote object with no enclosing quotes on the line → return `nil`, operator fizzles.
- Bracket object with no enclosing brackets → return `nil`.
- `aw` at EOL with no trailing space → include the leading space instead.

Tests cover each of these explicitly.

## Verification Plan

### Unit tests

`test/test_text_object.rb`:

- Word: cursor in middle, on whitespace, at EOL, multibyte chars in word.
- WORD: separators ignored that aren't whitespace.
- Quotes: nearest pair, cursor on quote, escaped quotes inside, no pair.
- Brackets: nesting (`(a (b) c)`), multiline, cursor on bracket, no pair.
- Paragraph: between paragraphs, on blank line, at file boundaries.
- Inclusive variants for each.

`test/test_editor.rb` additions:

- `dw`, `d$`, `db` work (regression coverage).
- `cw`, `yw`, `cc`, `yy` work.
- `diw`, `daw`, `ciw`, `yi(`, `da{`, `dap`.

### PTY end-to-end

1. `daw` deletes a word with surrounding space.
2. `ci"` clears a string body and drops into insert.
3. `yi(` yanks parens contents; `p` pastes.
4. `dap` deletes a paragraph block.
5. `da{` deletes a brace-delimited block including braces.
6. Nested: `di(` from inside `(a (b) c)` deletes the *inner* parens.
7. `dw` (regression) deletes one word.
8. `c$` (regression) changes to EOL.
9. `vit` extends visual selection to inside tag — **out of scope, expect fail or skip**.
10. `2diw` deletes two inner words.

## Out of scope (deferred)

- `it` / `at` (HTML/XML tags) — needs tag matching, deferred.
- `is` / `as` (sentences) — semantic regex tuning, deferred.
- `ib` / `iB` aliases — trivial to add later.
- `i_` / `a_` underscore objects (some plugins) — non-standard.
- Operator-pending counts on text objects beyond `2diw` (i.e., `d2iw` form) — Reline puts vi_arg on the operator; vim accepts both positions but the second form is rarer.

## Stages

Each ends with a verification step.

1. **Operator-pending refactor** — drop `rvim_d_prefix` binding; override `vi_delete_meta`/`_confirm`, `vi_change_meta`/`_confirm`, `vi_yank`/`_confirm` to handle linewise shortcuts and capture clipboard with kind tags. Verify `dd`, `dw`, `cw`, `yw`, `cc`, `yy`, `c$`, `db` all behave correctly.
2. **Text-object dispatch infrastructure** — `update` intercepts `i`/`a` during operator-pending; `Rvim::TextObject.find` dispatch shell with stub returns. No actual objects yet, but `diw` should at least not crash.
3. **Word objects (`iw`/`aw`/`iW`/`aW`)** — full word/WORD detection with inclusive variants. Tests for each edge case.
4. **Quote objects (`i"`/`a"`/`i'`/`a'`/`` i` ``/`` a` ``)** — same-char balance with cursor-on-quote disambiguation.
5. **Bracket objects (`i(`/`a(`/`i[`/`a[`/`i{`/`a{`/`i<`/`a<`)** — open-close nesting walk; aliases `b`/`B`.
6. **Paragraph objects (`ip`/`ap`)** — blank-line-delimited linewise selections.
7. **Visual mode text objects** — `vit`, `dap` from visual via `i`/`a` intercept in `intercept_visual_key`.
8. **PTY end-to-end** — run all 10 verification scenarios; iterate fixes.

Stretch (only if time remains):
- Operator-pending count propagation for text objects (`2diw`).
- `Esc` cancels operator-pending cleanly (probably already works via Reline, verify).
