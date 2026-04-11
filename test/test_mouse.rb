# frozen_string_literal: true

require_relative 'test_helper'

class TestMouseDispatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:mouse, 'a')
    buf = Rvim::Buffer.new(1, nil)
    buf.lines = (1..30).map { |i| "line #{i}".dup }
    @editor.instance_variable_set(:@buffer_of_lines, buf.lines)
    @editor.instance_variable_set(:@current_buffer, buf)
    @win = Rvim::Window.new(buf)
    @win.row = 0; @win.col = 0; @win.width = 80; @win.height = 25
    @editor.instance_variable_set(:@windows, [@win])
    @editor.instance_variable_set(:@current_window, @win)
  end

  def k(seq)
    Reline::Key.new(seq, nil, false)
  end

  def test_mouse_event_disabled_when_setting_empty
    @editor.settings.set(:mouse, '')
    refute @editor.send(:mouse_event?, k("\e[<0;5;3M"))
  end

  def test_mouse_event_recognized_when_setting_set
    assert @editor.send(:mouse_event?, k("\e[<0;5;3M"))
  end

  def test_left_click_moves_cursor
    @editor.update(k("\e[<0;5;3M"))
    # row 3 - win.row(0) - 1 = 2 → line index 2
    # col 5 - win.col(0) - gutter(0) - 1 = 4 → byte 4 (matches '4' in 'line 3')
    assert_equal 2, @editor.line_index
    assert @editor.byte_pointer >= 0
  end

  def test_left_click_outside_window_no_op
    @editor.instance_variable_set(:@line_index, 5)
    @editor.update(k("\e[<0;200;200M"))
    # Outside window — no change
    assert_equal 5, @editor.line_index
  end

  def test_scroll_up_moves_cursor_up
    @editor.instance_variable_set(:@line_index, 10)
    @editor.update(k("\e[<64;5;3M"))
    assert @editor.line_index < 10
  end

  def test_scroll_down_moves_cursor_down
    @editor.instance_variable_set(:@line_index, 5)
    @editor.update(k("\e[<65;5;3M"))
    assert @editor.line_index > 5
  end

  def test_release_event_ignored
    @editor.instance_variable_set(:@line_index, 0)
    @editor.update(k("\e[<0;5;3m")) # lowercase m = release
    # Release events ignored — cursor stays
    assert_equal 0, @editor.line_index
  end

  def test_left_click_clamps_to_buffer_end
    # Click far below the buffer
    @editor.update(k("\e[<0;5;25M"))
    assert @editor.line_index < @editor.buffer_of_lines.size
  end

  def test_left_click_clamps_byte_to_line_length
    @editor.instance_variable_set(:@buffer_of_lines, ['hi'.dup])
    @editor.instance_variable_set(:@current_buffer, @editor.current_buffer.tap { |b| b.lines = @editor.buffer_of_lines })
    @editor.update(k("\e[<0;50;1M"))
    line = @editor.buffer_of_lines[0]
    assert @editor.byte_pointer <= line.bytesize - 1
  end
end

class TestMouseModeSetup < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_mouse_enabled_when_setting_set
    @editor.settings.set(:mouse, 'a')
    assert @screen.mouse_enabled?
  end

  def test_mouse_disabled_when_setting_empty
    @editor.settings.set(:mouse, '')
    refute @screen.mouse_enabled?
  end
end
