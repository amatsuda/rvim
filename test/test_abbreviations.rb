# frozen_string_literal: true

require_relative 'test_helper'

class TestAbbreviationsBasic < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_iabbrev_adds_to_insert_only
    Rvim::Command.execute(@editor, Rvim::Command.parse(':iabbrev teh the'))
    refute_nil @editor.abbreviations.lookup(:insert, 'teh')
    assert_nil @editor.abbreviations.lookup(:cmdline, 'teh')
  end

  def test_cabbrev_adds_to_cmdline_only
    Rvim::Command.execute(@editor, Rvim::Command.parse(':cabbrev W w'))
    assert_nil @editor.abbreviations.lookup(:insert, 'W')
    refute_nil @editor.abbreviations.lookup(:cmdline, 'W')
  end

  def test_abbrev_adds_to_both
    Rvim::Command.execute(@editor, Rvim::Command.parse(':abbrev hi hello'))
    refute_nil @editor.abbreviations.lookup(:insert, 'hi')
    refute_nil @editor.abbreviations.lookup(:cmdline, 'hi')
  end

  def test_iunabbrev_removes
    Rvim::Command.execute(@editor, Rvim::Command.parse(':iabbrev teh the'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':iunabbrev teh'))
    assert_nil @editor.abbreviations.lookup(:insert, 'teh')
  end

  def test_iabclear_removes_all_insert
    Rvim::Command.execute(@editor, Rvim::Command.parse(':iabbrev teh the'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':iabbrev fr from'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':iabclear'))
    assert_nil @editor.abbreviations.lookup(:insert, 'teh')
    assert_nil @editor.abbreviations.lookup(:insert, 'fr')
  end

  def test_inoreabbrev_marks_non_recursive
    Rvim::Command.execute(@editor, Rvim::Command.parse(':inoreabbrev teh the'))
    entry = @editor.abbreviations.lookup(:insert, 'teh')
    refute_nil entry
    assert_equal false, entry.recursive
  end
end

class TestAbbrevDetect < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':iabbrev teh the'))
  end

  def test_detect_finds_word_before_terminator
    # User just typed 'teh ' (with trailing space). byte_pointer is at 4.
    line = +'teh '
    detection = @editor.abbreviations.detect(line, 4, :insert)
    refute_nil detection
    word_start, word_end, _entry = detection
    assert_equal 0, word_start
    assert_equal 3, word_end
  end

  def test_detect_finds_word_in_middle
    # User typed 'foo teh ' — word at bytes 4..6
    line = +'foo teh '
    detection = @editor.abbreviations.detect(line, 8, :insert)
    refute_nil detection
    assert_equal 4, detection[0]
    assert_equal 7, detection[1]
  end

  def test_detect_returns_nil_for_unmatched_word
    line = +'foo '
    detection = @editor.abbreviations.detect(line, 4, :insert)
    assert_nil detection
  end
end

class TestAbbrevCmdlineExpansion < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':cabbrev W write'))
  end

  def test_cabbrev_expands_in_prompt
    @editor.send(:rvim_enter_command_mode, nil)
    'W '.each_char { |ch| @editor.send(:process_prompt_key, Reline::Key.new(ch, nil, false)) }
    # 'W ' should have expanded to 'write '
    assert_equal 'write ', @editor.command_buffer
  end
end
