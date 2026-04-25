# frozen_string_literal: true

require_relative 'test_helper'

class TestHelpCommand < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_help_no_topic_opens_help_buffer
    Rvim::Command.execute(@editor, Rvim::Command.parse(':help'))
    assert_equal Rvim::Editor::HELP_PATH, @editor.filepath
    refute_empty @editor.buffer_of_lines
  end

  def test_help_topic_jumps_to_tag
    Rvim::Command.execute(@editor, Rvim::Command.parse(':help :wq'))
    line = @editor.buffer_of_lines[@editor.line_index]
    assert_match(/\*:wq\*/, line.to_s)
  end

  def test_help_unknown_topic_warns
    Rvim::Command.execute(@editor, Rvim::Command.parse(':help bogus_topic_12345'))
    assert_match(/E149/, @editor.status_message.to_s)
  end

  def test_help_navigation_topic
    Rvim::Command.execute(@editor, Rvim::Command.parse(':help navigation'))
    line = @editor.buffer_of_lines[@editor.line_index]
    assert_match(/\*navigation\*/, line.to_s)
  end

  def test_help_text_objects_topic
    Rvim::Command.execute(@editor, Rvim::Command.parse(':help text-objects'))
    line = @editor.buffer_of_lines[@editor.line_index]
    assert_match(/\*text-objects\*/, line.to_s)
  end
end
