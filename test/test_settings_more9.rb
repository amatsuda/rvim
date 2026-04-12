# frozen_string_literal: true

require_relative 'test_helper'

class TestTitle < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:title)
  end

  def test_render_title_with_filepath
    @editor.instance_variable_set(:@filepath, '/path/to/foo.rb')
    out = @screen.send(:render_title)
    assert_equal "\e]0;foo.rb - rvim\a", out
  end

  def test_render_title_with_no_filepath
    out = @screen.send(:render_title)
    assert_equal "\e]0;[No Name] - rvim\a", out
  end

  def test_render_title_with_custom_titlestring
    @editor.settings.set(:titlestring, 'MyEditor')
    out = @screen.send(:render_title)
    assert_equal "\e]0;MyEditor\a", out
  end

  def test_tl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tl'))
    assert_equal true, @editor.settings.get(:title)
  end
end

class TestShowtabline < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
    # Build a tabs list with two tabs so showtabline=1 should show
    buf = Rvim::Buffer.new(1, nil)
    win = Rvim::Window.new(buf)
    tab1 = Rvim::Tab.new(win)
    tab2 = Rvim::Tab.new(Rvim::Window.new(buf))
    @editor.instance_variable_set(:@tabs, [tab1, tab2])
  end

  def test_default_1_shows_only_when_multi_tab
    @editor.settings.set(:showtabline, 1)
    assert_equal 1, @screen.send(:tabline_height)
    @editor.instance_variable_set(:@tabs, [@editor.tabs.first])
    assert_equal 0, @screen.send(:tabline_height)
  end

  def test_zero_never_shows
    @editor.settings.set(:showtabline, 0)
    assert_equal 0, @screen.send(:tabline_height)
  end

  def test_two_always_shows
    @editor.settings.set(:showtabline, 2)
    @editor.instance_variable_set(:@tabs, [@editor.tabs.first])
    assert_equal 1, @screen.send(:tabline_height)
  end

  def test_stal_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set stal=2'))
    assert_equal 2, @editor.settings.get(:showtabline)
  end
end

class TestScrolljump < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, (1..100).map { |i| "line #{i}".dup })
    buf = Rvim::Buffer.new(1, nil); buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    @win = Rvim::Window.new(buf); @win.height = 21; @win.row = 0; @win.col = 0
    @editor.instance_variable_set(:@windows, [@win])
    @editor.instance_variable_set(:@current_window, @win)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_one_minimal_scroll
    @editor.settings.set(:scrolljump, 1)
    @editor.instance_variable_set(:@line_index, 21)
    @win.scroll_top = 0
    @screen.send(:adjust_window_scroll, @win, 20)
    assert_equal 2, @win.scroll_top
  end

  def test_scrolljump_larger_jump
    @editor.settings.set(:scrolljump, 5)
    @editor.instance_variable_set(:@line_index, 21)
    @win.scroll_top = 0
    @screen.send(:adjust_window_scroll, @win, 20)
    # Min jump 5 → scroll_top becomes 5 instead of 2
    assert_equal 5, @win.scroll_top
  end

  def test_scrolljump_does_not_overshoot_when_cursor_far_below
    @editor.settings.set(:scrolljump, 3)
    @editor.instance_variable_set(:@line_index, 50)
    @win.scroll_top = 0
    @screen.send(:adjust_window_scroll, @win, 20)
    # Cursor needs to be visible — scroll_top must be at least 31
    # min jump of 3 from 0 → 3, but cursor at 50 needs scroll_top >= 31
    assert_equal 31, @win.scroll_top
  end

  def test_sj_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sj=10'))
    assert_equal 10, @editor.settings.get(:scrolljump)
  end
end
