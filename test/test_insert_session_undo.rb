# frozen_string_literal: true

require_relative 'test_helper'

# Every key in insert mode used to be its own undo step (Reline's
# default). Vim/NeoVim treat a whole insert session (i...Esc) as a
# SINGLE undo step. This collapses Reline's per-keystroke history
# into one entry on insert-leave.

class TestInsertSessionUndo < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+''])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.config.editing_mode = :vi_command
  end

  # Simulate the lifecycle of an insert session: enter insert mode,
  # type some chars (each gets pushed to undo via Reline's super),
  # then leave insert mode (triggers the collapse).
  def insert_session(text)
    @editor.config.editing_mode = :vi_insert
    @editor.instance_variable_set(:@insert_undo_start_index,
                                  @editor.instance_variable_get(:@undo_redo_index))
    text.each_char do |ch|
      line = @editor.buffer_of_lines[@editor.line_index]
      @editor.buffer_of_lines[@editor.line_index] = line + ch
      @editor.instance_variable_set(:@byte_pointer, @editor.byte_pointer + ch.bytesize)
      # Reline's per-key push
      @editor.send(:push_undo_redo, true)
    end
    @editor.config.editing_mode = :vi_command
    @editor.send(:collapse_insert_undo_history)
  end

  def history
    @editor.instance_variable_get(:@undo_redo_history)
  end

  def index
    @editor.instance_variable_get(:@undo_redo_index)
  end

  def test_per_keystroke_entries_collapse_to_one_on_leave
    pre = history.size
    insert_session('hello')
    # One additional entry after collapse: the final post-insert state.
    assert_equal pre + 1, history.size
    assert_equal 'hello', @editor.buffer_of_lines[0]
  end

  def test_undo_after_insert_session_jumps_to_pre_insert
    insert_session('hello')
    @editor.send(:undo, nil)
    assert_equal '', @editor.buffer_of_lines[0]
  end

  def test_redo_replays_the_full_session
    insert_session('hello')
    @editor.send(:undo, nil)
    assert_equal '', @editor.buffer_of_lines[0]
    @editor.send(:redo, nil)
    assert_equal 'hello', @editor.buffer_of_lines[0]
  end

  def test_two_separate_sessions_are_independent_undo_steps
    insert_session('abc')
    insert_session('def')
    assert_equal 'abcdef', @editor.buffer_of_lines[0]

    @editor.send(:undo, nil)
    assert_equal 'abc', @editor.buffer_of_lines[0]
    @editor.send(:undo, nil)
    assert_equal '', @editor.buffer_of_lines[0]
  end

  def test_empty_insert_session_does_not_corrupt_history
    pre = history.size
    @editor.config.editing_mode = :vi_insert
    @editor.instance_variable_set(:@insert_undo_start_index,
                                  @editor.instance_variable_get(:@undo_redo_index))
    @editor.config.editing_mode = :vi_command
    @editor.send(:collapse_insert_undo_history)
    assert_equal pre, history.size, 'no new entries when no edits happened'
  end

  def test_single_keystroke_session_keeps_one_entry
    pre = history.size
    insert_session('x')
    # Single key → only one entry added before collapse, collapse is a no-op.
    assert_equal pre + 1, history.size
    @editor.send(:undo, nil)
    assert_equal '', @editor.buffer_of_lines[0]
  end
end
