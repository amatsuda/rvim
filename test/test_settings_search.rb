# frozen_string_literal: true

require_relative 'test_helper'

class TestMagicStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:magic)
  end

  def test_set_nomagic
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nomagic'))
    assert_equal false, @editor.settings.get(:magic)
  end
end

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

class TestRegexpengineStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero_auto
    assert_equal 0, @editor.settings.get(:regexpengine)
  end

  def test_re_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set re=2'))
    assert_equal 2, @editor.settings.get(:regexpengine)
  end
end

class TestGdefaultStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:gdefault)
  end

  def test_gd_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set gd'))
    assert_equal true, @editor.settings.get(:gdefault)
  end
end

class TestIncsearchSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'foo bar foo'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_incsearch_on_updates_matches_during_typing
    @editor.settings.set(:incsearch, true)
    @editor.send(:rvim_enter_search_forward, nil)
    'foo'.each_char { |c| @editor.send(:process_prompt_key, Reline::Key.new(c, nil, false)) }
    refute_empty @editor.search_matches
  end

  def test_incsearch_off_does_not_update_matches
    @editor.settings.set(:incsearch, false)
    @editor.send(:rvim_enter_search_forward, nil)
    'foo'.each_char { |c| @editor.send(:process_prompt_key, Reline::Key.new(c, nil, false)) }
    assert_empty @editor.search_matches
  end
end
