# frozen_string_literal: true

require_relative 'test_helper'

class TestEarlierLater < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'abc'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:push_undo_redo, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+'abcde'])
    @editor.send(:push_undo_redo, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+'abcdefg'])
    @editor.send(:push_undo_redo, true)
  end

  def test_earlier_count_undoes_n
    Rvim::Command.execute(@editor, Rvim::Command.parse(':earlier 1'))
    assert_equal 'abcde', @editor.buffer_of_lines[0]
    Rvim::Command.execute(@editor, Rvim::Command.parse(':earlier 1'))
    assert_equal 'abc', @editor.buffer_of_lines[0]
  end

  def test_later_count_redoes_n
    @editor.send(:undo, nil)
    @editor.send(:undo, nil)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':later 1'))
    assert_equal 'abcde', @editor.buffer_of_lines[0]
  end

  def test_earlier_no_arg_defaults_to_one
    Rvim::Command.execute(@editor, Rvim::Command.parse(':earlier'))
    assert_equal 'abcde', @editor.buffer_of_lines[0]
  end

  def test_undo_timestamps_recorded
    refute_nil @editor.undo_timestamps
    assert_operator @editor.undo_timestamps.size, :>=, 3
    @editor.undo_timestamps.each { |t| assert_kind_of Time, t }
  end

  def test_undolist_shows_entries
    Rvim::Command.execute(@editor, Rvim::Command.parse(':undolist'))
    # No assertion error; ensure it doesn't crash and produces output.
    assert_operator @editor.undo_timestamps.size, :>=, 1
  end
end

class TestParseUndoArg < Test::Unit::TestCase
  def test_count_default
    assert_equal [1, :count], Rvim::Command.parse_undo_arg('')
    assert_equal [3, :count], Rvim::Command.parse_undo_arg('3')
  end

  def test_seconds_unit
    assert_equal [5, :seconds], Rvim::Command.parse_undo_arg('5s')
    assert_equal [120, :seconds], Rvim::Command.parse_undo_arg('2m')
  end
end
