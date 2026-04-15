# frozen_string_literal: true

require_relative 'test_helper'

class TestWrapscan < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:wrapscan)
  end

  def test_ws_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nowrapscan'))
    assert_equal false, @editor.settings.get(:wrapscan)
  end

  def test_search_wraps_when_on
    @editor.instance_variable_set(:@buffer_of_lines, ['foo'.dup, 'bar'.dup, 'foo'.dup])
    @editor.instance_variable_set(:@line_index, 2)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.instance_variable_set(:@search_pattern, 'foo')
    @editor.instance_variable_set(:@search_matches, Rvim::Search.scan(@editor.buffer_of_lines, 'foo'))
    @editor.send(:jump_to_search, :forward)
    assert_equal 0, @editor.line_index
  end

  def test_search_does_not_wrap_when_off
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nowrapscan'))
    @editor.instance_variable_set(:@buffer_of_lines, ['foo'.dup, 'bar'.dup, 'foo'.dup])
    @editor.instance_variable_set(:@line_index, 2)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.instance_variable_set(:@search_pattern, 'foo')
    @editor.instance_variable_set(:@search_matches, Rvim::Search.scan(@editor.buffer_of_lines, 'foo'))
    @editor.send(:jump_to_search, :forward)
    # Cursor stays put since no forward match exists past line 2.
    assert_equal 2, @editor.line_index
    assert_match(/E385/, @editor.status_message.to_s)
  end
end

class TestCmdheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one
    assert_equal 1, @editor.settings.get(:cmdheight)
  end

  def test_ch_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ch=2'))
    assert_equal 2, @editor.settings.get(:cmdheight)
  end
end

class TestReportStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_two
    assert_equal 2, @editor.settings.get(:report)
  end

  def test_set_report
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set report=10'))
    assert_equal 10, @editor.settings.get(:report)
  end
end

class TestIskeywordStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default
    assert_match(/192-255/, @editor.settings.get(:iskeyword))
  end

  def test_isk_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set isk=a-z,A-Z,_'))
    assert_equal 'a-z,A-Z,_', @editor.settings.get(:iskeyword)
  end
end

class TestMatchpairsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_pairs
    assert_equal '(:),{:},[:]', @editor.settings.get(:matchpairs)
  end

  def test_mps_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mps=(:),{:},[:],<:>'))
    assert_equal '(:),{:},[:],<:>', @editor.settings.get(:matchpairs)
  end
end
