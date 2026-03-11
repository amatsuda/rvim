# Rvim v1.4: Repeat (`.`) + Macros (`q` / `@`) — Design Spec

## Context

After v1.3 the editor has a full set of editing primitives. The next layer is *playback*: the ability to repeat the last edit (`.`) and to record/replay arbitrary keystroke sequences (macros via `q`/`@`). Both depend on the same idea — buffer keystrokes as they're pressed, save them to a replayable slot, and feed them back through `update(key)` later.

This plan covers:

- `.` — repeat the last buffer-modifying action (insert sequence, operator+motion, operator+text-object, linewise shortcut, single-shot like `x`/`p`/`~`/`>>`)
- `q<reg>` — start recording into named register `<reg>` (single lowercase letter)
- `q` (alone, while recording) — stop and store the recorded keys
- `@<reg>` — replay the recorded sequence from register `<reg>`
- `@@` — replay the last `@` invocation
- A minimal `@registers` hash, keyed by single-char register name. Used **only** for macros in this plan; full clipboard register integration (`"ay`, `"ap`) defers to a follow-up.

Out of scope:

- Visual-mode `.` (vim's `.` after a visual op replays the operator on a same-shape range from cursor — complex, deferred)
- Clipboard register integration (`"ay`, `"ap`)
- `:registers` listing
- Numbered registers `"0-"9`
- Special registers (`""` unnamed, `"+` system, `"_` blackhole)

## Architecture

### What gets recorded

Both `.` and macros buffer keystrokes, but with different scoping rules:

| | `.` (last change) | `q<reg>` macro |
|---|---|---|
| Records | Only buffer-modifying sequences | Every keystroke until `q` again |
| Includes motions between edits? | No | Yes |
| Includes ex commands / search? | No | Yes |
| Frozen at | End of one logical change | When user presses `q` again |

We split the two concerns into two recorders:

- **`@change_keys`** — currently-accumulating keystrokes since the last "clean idle" boundary in normal mode. When a logical change completes, copy these into `@last_change_keys`. `.` replays `@last_change_keys`.
- **`@macro_keys`** + **`@macro_register`** — keystroke buffer + the target register name. Active only while `q<reg>...q` is recording. On stop, `@registers[reg] = @macro_keys.dup`.

### Defining a "clean idle" boundary

Normal mode (`vi_command`), no pending state:

- `@vi_waiting_operator.nil?` (no `d`/`c`/`y` waiting for motion)
- `@rvim_text_object_pending.nil?` (no `i`/`a` waiting for object)
- `@waiting_proc.nil?` (no two-key sequence in progress)
- `@visual_mode.nil?` (not in visual)
- `@prompt_mode.nil?` (not in `:`/`/`/`?` prompt)
- `@config.editing_mode_label == :vi_command` (not in insert)

When `update(key)` is called and the editor *was* at a clean idle boundary before the key, start fresh recording: `@change_keys = [key]`. Otherwise append: `@change_keys << key`.

After `super` runs, if the editor is *back* at a clean idle boundary AND the buffer changed during this update, freeze: `@last_change_keys = @change_keys.dup; @change_keys = []`.

This catches all the right cases:

- `iXYZ<Esc>`: starts at `i`, ends at `<Esc>` (back to vi_command, buffer changed) → freeze 5 keys.
- `dw`: starts at `d`, ends at `w` (operator pending cleared, buffer changed) → freeze 2 keys.
- `ciw`: starts at `c`, ends after `c i w X<Esc>` if user typed something → freeze the whole sequence.
- `>>`: starts at first `>`, ends at second (waiting_proc cleared, buffer changed) → freeze 2 keys.
- Pure motion `j`: no buffer change, recording cleared without freezing.
- `:wq` Enter: prompt mode active, recording paused / discarded.

### Replaying

`.` replays `@last_change_keys` by feeding each key back through `update(key)`. The keys are `Reline::Key` objects (we save them as-is during recording). Reline's dispatch handles them exactly as if the user typed them.

Caveat: while `.` replays, we must not let the replay itself enter the recorder — otherwise repeating the dot would clobber `@last_change_keys`. Set a `@replaying` flag to suppress recording during replay.

Macros work identically — `@<reg>` feeds `@registers[reg]` through `update`, with `@replaying = true` for the duration.

### File layout (additive)

```
lib/rvim/
  recorder.rb       # NEW — small module that owns the change-recording state machine
  editor.rb         # @change_keys / @last_change_keys / @registers / @replaying;
                    # update() wraps super with recorder calls;
                    # bind . / q / @ / @@
test/
  test_recorder.rb  # NEW — boundary detection, replay equivalence
  test_editor.rb    # add . and macro PTY-style tests
```

`recorder.rb` keeps the boundary logic out of `editor.rb`. It exposes:

```ruby
Rvim::Recorder.new
  .at_idle?(editor)              # bool
  .start_or_append(editor, key)  # called pre-super
  .freeze_if_settled(editor, before_buffer)  # called post-super
```

But honestly the logic is small; we may inline it on the editor and skip the separate file. Decide during Stage 1.

## Components

### 1. Change recording (Editor)

```ruby
@change_keys           # Array<Reline::Key>, in-flight recording
@last_change_keys      # Array<Reline::Key>, last frozen change
@replaying             # Boolean — true during . / @ playback
```

In `update(key)`:

```ruby
def update(key)
  was_idle = idle_for_recording?
  before_buffer = @buffer_of_lines.map(&:dup)

  if @recording_macro
    @macro_keys << key unless macro_terminator?(key)
  end
  unless @replaying
    if was_idle
      @change_keys = [key]
    else
      @change_keys << key
    end
  end

  # ... existing branches dispatching to super, intercept_visual_key, etc. ...

  if !@replaying && idle_for_recording? && before_buffer != @buffer_of_lines
    @last_change_keys = @change_keys.dup
    @change_keys = []
  end
end
```

`idle_for_recording?` is the AND of all the pending-state checks listed above.

`macro_terminator?` returns true for the `q` keystroke that *ends* a macro recording (so the terminator itself isn't replayed) but not for any other `q`. Simple way: when we receive `q` and `@recording_macro` is true, mark this key as the terminator and don't append.

### 2. `.` repeat (Editor)

Bind `.` (0x2E) in `vi_command` to `:rvim_dot`:

```ruby
private def rvim_dot(key)
  return if @last_change_keys.empty?
  @replaying = true
  @last_change_keys.each { |k| update(k) }
ensure
  @replaying = false
end
```

Counts: `5.` should replay the change 5 times. Reline's `vi_arg` pipes into the binding; we'd accept `arg:` and loop.

### 3. Macro recording (Editor)

```ruby
@registers = {}        # { 'a' => [Reline::Key, ...], ... }
@recording_macro       # nil or 'a'..'z' (the register being recorded into)
@macro_keys            # current macro recording buffer
@last_macro_register   # for @@
```

Bind `q` in `vi_command` to `:rvim_q_prefix`:

```ruby
private def rvim_q_prefix(key)
  if @recording_macro
    @registers[@recording_macro] = @macro_keys.dup
    @recording_macro = nil
    @macro_keys = []
    @status_message = "Recorded into @#{@recording_macro}"
  else
    # Wait for the register name.
    @waiting_proc = lambda do |reg_key, _sym|
      @waiting_proc = nil
      ch = reg_key.is_a?(Integer) ? reg_key.chr : reg_key.to_s
      if ch =~ /\A[a-z]\z/
        @recording_macro = ch
        @macro_keys = []
        @status_message = "Recording @#{ch}"
      end
    end
  end
end
```

Bind `@` in `vi_command` to `:rvim_at_prefix`:

```ruby
private def rvim_at_prefix(key)
  @waiting_proc = lambda do |reg_key, _sym|
    @waiting_proc = nil
    ch = reg_key.is_a?(Integer) ? reg_key.chr : reg_key.to_s
    target = ch == '@' ? @last_macro_register : ch
    keys = @registers[target]
    return unless keys

    @last_macro_register = target
    @replaying = true
    keys.each { |k| update(k) }
    @replaying = false
  end
end
```

The `@@` form is handled by checking `ch == '@'` — replay the last register.

### 4. Status display (Screen)

Show the recording state in the status line so users can see they're in macro mode. Existing `@status_message` is fine for transient text; for *persistent* "recording" indicator we add a small badge to the right of `[Normal]`:

```
[Normal] file.rb [+]    L:C  pct%  recording @a
```

Just a string concatenation in `Screen#status_line` keyed off `@editor.recording_macro`.

## Key Technical Decisions

### Why feed-keys-through-update for replay?

Alternatives:

1. **Reconstruct semantic actions**: when `dw` is recorded, save `{op: :delete, motion: :word}` and re-execute. Cleaner for inspection, but means duplicating Reline's dispatch in the replay path.
2. **Save a "redo log" of buffer ops**: directly re-apply byte-level changes. Fast but breaks if cursor position differs at replay time (which is the *whole point* of `.`).
3. **Feed keys back through `update(key)`** (this design). Lets Reline's dispatch do the work; the replay is automatically context-sensitive (cursor at new position drives motion correctly).

#3 wins on correctness and code reuse. The only complication is the `@replaying` flag to prevent re-recording.

### Where does the recording start?

We want `.` to repeat what the user *meant*, not what they *typed*. Vim's heuristic: a "change" begins when entering insert mode or starting an operator, and ends when both are resolved.

Translating to our state machine: a change starts when we leave the clean-idle state, ends when we return. This naturally batches:

- `iXYZ<Esc>` — leaves at `i`, returns at `<Esc>` (5 keys recorded)
- `dw` — leaves at `d`, returns when motion resolves (2 keys)
- `c i w X Y <Esc>` — leaves at `c`, returns at `<Esc>` (6 keys)
- `j j j` — never leaves clean-idle (no buffer change), discarded

Edge case: `r<char>` (replace one char). Not in our editor yet. When added, it should also be a single-shot change captured by the boundary logic.

### Replay re-entry

When `.` calls `update(k)` for each recorded key, those calls go through the same `update` we're currently inside of. Pure functions handle re-entry fine, but our `@change_keys` accumulator would corrupt itself. The `@replaying` flag short-circuits the recorder for the duration of the replay loop.

### Macro recording and `q`

`q<reg>` starts recording. The register-name key (`<reg>`) is consumed by the waiting_proc and **not** appended to the recording. When `q` is pressed to stop, that `q` is also not appended. Easy because we set the recording-state flag *after* `rvim_q_prefix`'s waiting_proc runs.

### Empty macros, missing registers

`@<reg>` with no recording in `<reg>` is a silent no-op (vim warns; we'll match). `@@` with no prior `@` does nothing.

## Verification Plan

### Unit tests

`test/test_recorder.rb`:

- `idle_for_recording?` returns false during operator-pending, text-object-pending, insert mode, visual, prompt.
- After `i X Y Z <Esc>` simulated through update, `@last_change_keys` has 5 keys.
- After `d w`, `@last_change_keys` has 2 keys.
- Pure motion (`j j j`) doesn't update `@last_change_keys`.
- `.` after `iX<Esc>` produces `XX` (original X + replayed X) at cursor.

### PTY end-to-end

1. `iX<Esc>` then `.` → buffer has two `X`s.
2. `dw` then `.` → two words removed.
3. `ciw NEW <Esc>` then `.` on next word → next word becomes `NEW`.
4. `>>` then `.` → line indented twice.
5. `5.` → previous change repeated 5 times.
6. `qa iX<Esc> q` then `@a` → buffer has two `X`s.
7. `qa j q` then `5@a` → cursor advances 5 lines (motion in macro).
8. `@@` after one `@a` → repeats `@a`.
9. `qa qb` (zero-length recording into a, then b takes over) — graceful handling.
10. `.` before any change has been made — silent no-op, no crash.

## Stages

1. **Recording state machine** — `@change_keys`, `idle_for_recording?`, freeze logic in `update`. `@last_change_keys` populated but unused. Unit tests for boundaries.
2. **`.` repeat** — bind `.`, replay `@last_change_keys` with `@replaying` guard. Counts via `arg:`.
3. **Macro register table** — `@registers`, `@recording_macro`, `@macro_keys`, `@last_macro_register`. Status line badge while recording.
4. **`q` prefix** — `rvim_q_prefix` with waiting_proc for register name; second `q` stops recording.
5. **`@` prefix** — `rvim_at_prefix` with waiting_proc; supports `@@` for last macro.
6. **PTY end-to-end** — run all 10 verification scenarios; iterate.

Stretch:

- Visual-mode `.` (replay last operator over a same-shape range) — defer.
- `:registers` listing command — defer to the registers plan.
