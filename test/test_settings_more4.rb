# frozen_string_literal: true

require_relative 'test_helper'

class TestSplitDirection < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    buf = Rvim::Buffer.new(1, nil)
    @editor.instance_variable_set(:@current_buffer, buf)
    @initial = Rvim::Window.new(buf)
    @editor.instance_variable_set(:@windows, [@initial])
    @editor.instance_variable_set(:@current_window, @initial)
  end

  def test_default_horizontal_inserts_before_current
    @editor.split_horizontal
    # default splitbelow=false → new split goes BEFORE the current
    assert_equal @editor.windows.first, @editor.current_window
    assert_equal @initial, @editor.windows.last
  end

  def test_splitbelow_inserts_after_current
    @editor.settings.set(:splitbelow, true)
    @editor.split_horizontal
    assert_equal @initial, @editor.windows.first
    assert_equal @editor.current_window, @editor.windows.last
  end

  def test_default_vertical_inserts_before_current
    @editor.split_vertical
    assert_equal @editor.current_window, @editor.windows.first
    assert_equal @initial, @editor.windows.last
  end

  def test_splitright_inserts_after_current
    @editor.settings.set(:splitright, true)
    @editor.split_vertical
    assert_equal @initial, @editor.windows.first
    assert_equal @editor.current_window, @editor.windows.last
  end
end

class TestShowmodeSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    buf = Rvim::Buffer.new(1, nil); buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    @win = Rvim::Window.new(buf)
    @editor.instance_variable_set(:@current_window, @win)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_showmode_on_includes_mode_label
    @editor.settings.set(:showmode, true)
    out = @screen.send(:window_status, @win, true)
    assert_match(/\[(Normal|Visual|Insert)\]/, out)
  end

  def test_showmode_off_omits_mode_label
    @editor.settings.set(:showmode, false)
    out = @screen.send(:window_status, @win, true)
    refute_match(/\[(Normal|Visual|Insert)\]/, out)
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

class TestLazyredrawSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @rendered = 0
    fake = Object.new
    counter = ->(*) { @rendered += 1 }
    fake.define_singleton_method(:render) { counter.call }
    @editor.instance_variable_set(:@screen, fake)
  end

  def test_default_renders_during_replay
    @editor.instance_variable_set(:@replaying, true)
    @editor.render
    assert_equal 1, @rendered
  end

  def test_lazyredraw_skips_render_during_replay
    @editor.settings.set(:lazyredraw, true)
    @editor.instance_variable_set(:@replaying, true)
    @editor.render
    assert_equal 0, @rendered
  end

  def test_lazyredraw_renders_when_not_replaying
    @editor.settings.set(:lazyredraw, true)
    @editor.instance_variable_set(:@replaying, false)
    @editor.render
    assert_equal 1, @rendered
  end
end

class TestSettingAliases < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_aliases_via_set
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set spr'))
    assert_equal true, @editor.settings.get(:splitright)

    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sb'))
    assert_equal true, @editor.settings.get(:splitbelow)

    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nosmd'))
    assert_equal false, @editor.settings.get(:showmode)

    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nois'))
    assert_equal false, @editor.settings.get(:incsearch)

    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lz'))
    assert_equal true, @editor.settings.get(:lazyredraw)
  end
end
