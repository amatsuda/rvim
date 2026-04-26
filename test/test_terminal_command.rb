# frozen_string_literal: true

require_relative 'test_helper'

class TestTerminalCommand < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_terminal_runs_command_and_captures_output
    Rvim::Command.execute(@editor, Rvim::Command.parse(":terminal echo hello"))
    assert_match(/hello/, @editor.buffer_of_lines.join)
  end

  def test_terminal_buffer_is_named_term_prefix
    Rvim::Command.execute(@editor, Rvim::Command.parse(":terminal echo hi"))
    assert_match(%r{term://}, @editor.filepath.to_s)
  end

  def test_terminal_status_message_includes_exit_code
    Rvim::Command.execute(@editor, Rvim::Command.parse(":terminal true"))
    assert_match(/exited 0/, @editor.status_message.to_s)
  end

  def test_terminal_captures_stderr
    Rvim::Command.execute(@editor, Rvim::Command.parse(":terminal echo oops 1>&2"))
    assert_match(/oops/, @editor.buffer_of_lines.join)
  end
end
