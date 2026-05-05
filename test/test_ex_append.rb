# frozen_string_literal: true

require_relative 'test_helper'

# :a / :append, :i / :insert, :c / :change — vim's ex-mode line input
# commands. After running the command the prompt enters a multi-line
# capture mode that collects each subsequent line; a single '.' ends
# input. The kinds differ in placement:
#   :a — insert AFTER target line
#   :i — insert BEFORE target line
#   :c — replace target range
class TestExAppend < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'line1', +'line2', +'line3'])
    @editor.instance_variable_set(:@line_index, 1) # on 'line2'
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.config.editing_mode = :vi_command
  end

  def feed_input(*lines)
    lines.each do |l|
      @editor.instance_variable_set(:@prompt_buffer, +l)
      @editor.send(:execute_prompt)
    end
  end

  def test_a_inserts_after_current_line
    Rvim::Command.execute(@editor, Rvim::Command.parse(':a'))
    assert_equal :ex_input, @editor.prompt_mode
    feed_input('new1', 'new2', '.')
    assert_equal ['line1', 'line2', 'new1', 'new2', 'line3'], @editor.buffer_of_lines
  end

  def test_i_inserts_before_current_line
    Rvim::Command.execute(@editor, Rvim::Command.parse(':i'))
    feed_input('NEW', '.')
    assert_equal ['line1', 'NEW', 'line2', 'line3'], @editor.buffer_of_lines
  end

  def test_c_replaces_current_line
    Rvim::Command.execute(@editor, Rvim::Command.parse(':c'))
    feed_input('replaced', '.')
    assert_equal ['line1', 'replaced', 'line3'], @editor.buffer_of_lines
  end

  def test_a_with_explicit_line_number
    Rvim::Command.execute(@editor, Rvim::Command.parse(':1a'))
    feed_input('after-1', '.')
    assert_equal ['line1', 'after-1', 'line2', 'line3'], @editor.buffer_of_lines
  end

  def test_a_with_no_lines_just_dot
    Rvim::Command.execute(@editor, Rvim::Command.parse(':a'))
    feed_input('.')
    assert_equal ['line1', 'line2', 'line3'], @editor.buffer_of_lines
    assert_nil @editor.prompt_mode
  end

  def test_a_ends_in_command_mode
    Rvim::Command.execute(@editor, Rvim::Command.parse(':a'))
    feed_input('x', '.')
    assert_nil @editor.prompt_mode
    assert_nil @editor.ex_input_state
  end

  def test_a_status_message_during_input
    Rvim::Command.execute(@editor, Rvim::Command.parse(':a'))
    assert_match(/APPEND/, @editor.status_message.to_s)
  end

  def test_c_with_range_replaces_block
    Rvim::Command.execute(@editor, Rvim::Command.parse(':1,2c'))
    feed_input('A', 'B', '.')
    assert_equal ['A', 'B', 'line3'], @editor.buffer_of_lines
  end

  def test_a_marks_buffer_modified
    @editor.instance_variable_set(:@modified, false)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':a'))
    feed_input('x', '.')
    assert_equal true, @editor.modified
  end
end
