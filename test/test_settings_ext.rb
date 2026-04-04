# frozen_string_literal: true

require_relative 'test_helper'

class TestSettingsAliases < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_set_tabstop_via_alias_ts
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ts=4'))
    assert_equal 4, @editor.settings.get(:tabstop)
  end

  def test_set_scrolloff_via_alias_so
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set so=3'))
    assert_equal 3, @editor.settings.get(:scrolloff)
  end

  def test_set_cursorline_via_alias_cul
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cul'))
    assert_equal true, @editor.settings.get(:cursorline)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nocul'))
    assert_equal false, @editor.settings.get(:cursorline)
  end

  def test_default_values
    assert_equal 8, @editor.settings.get(:tabstop)
    assert_equal 0, @editor.settings.get(:scrolloff)
    assert_equal false, @editor.settings.get(:cursorline)
    assert_equal true, @editor.settings.get(:ruler)
    assert_equal false, @editor.settings.get(:list)
  end
end

class TestRenderLineWithSettings < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_render_line_uses_tabstop
    @editor.settings.set(:tabstop, 4)
    assert_equal '    x', @screen.send(:render_line, "\tx")
  end

  def test_render_line_default_tabstop_8
    assert_equal '        x', @screen.send(:render_line, "\tx")
  end

  def test_render_line_with_list_tab_marker
    @editor.settings.set(:list, true)
    @editor.settings.set(:tabstop, 4)
    assert_equal '>---x', @screen.send(:render_line, "\tx")
  end

  def test_render_line_with_list_marks_trailing_whitespace
    @editor.settings.set(:list, true)
    assert_equal 'foo··', @screen.send(:render_line, 'foo  ')
  end

  def test_render_line_without_list_keeps_trailing_whitespace
    assert_equal 'foo  ', @screen.send(:render_line, 'foo  ')
  end
end

class TestScrolloffBehavior < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, (1..100).map { |i| +"line #{i}" })
    buf = Rvim::Buffer.new(1, nil)
    buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    @win = Rvim::Window.new(buf)
    @win.height = 21
    @editor.instance_variable_set(:@windows, [@win])
    @editor.instance_variable_set(:@current_window, @win)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_scrolloff_zero_default
    @editor.instance_variable_set(:@line_index, 50)
    @win.scroll_top = 50
    @screen.send(:adjust_window_scroll, @win, 20)
    assert_equal 50, @win.scroll_top
  end

  def test_scrolloff_keeps_context_above
    @editor.settings.set(:scrolloff, 3)
    @editor.instance_variable_set(:@line_index, 50)
    @win.scroll_top = 49 # cursor at row 1, less than offset of 3
    @screen.send(:adjust_window_scroll, @win, 20)
    assert_equal 47, @win.scroll_top # cursor - offset = 50 - 3
  end

  def test_scrolloff_keeps_context_below
    @editor.settings.set(:scrolloff, 3)
    @editor.instance_variable_set(:@line_index, 50)
    @win.scroll_top = 32 # cursor at row 18 of 20 — only 1 line below, need 3
    @screen.send(:adjust_window_scroll, @win, 20)
    # scroll_top = cursor - visible + offset + 1 = 50 - 20 + 3 + 1 = 34
    assert_equal 34, @win.scroll_top
  end
end

class TestRulerToggle < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    buf = Rvim::Buffer.new(1, nil)
    buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    @win = Rvim::Window.new(buf)
    @editor.instance_variable_set(:@current_window, @win)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_ruler_on_shows_position
    @editor.settings.set(:ruler, true)
    status = @screen.send(:window_status, @win, true)
    assert_match(/1,1/, status)
    assert_match(/100%/, status)
  end

  def test_ruler_off_hides_position
    @editor.settings.set(:ruler, false)
    status = @screen.send(:window_status, @win, true)
    refute_match(/1,1/, status)
    refute_match(/100%/, status)
  end
end
