# frozen_string_literal: true

require_relative 'test_helper'

# H / M / L jump to the top / middle / bottom of the current
# viewport (not the buffer). Cursor lands on first non-blank column.
# H and L accept a count: 2H = 2nd line from top; 3L = 3rd from bottom.

class TestWindowMotions < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    # 30-line buffer; lines numbered so we can assert.
    lines = (0..29).map { |i| "  line#{i}" }
    buf = Rvim::Buffer.new(1, '/tmp/x')
    buf.lines = lines
    @editor.instance_variable_set(:@buffer_of_lines, lines)
    @editor.instance_variable_set(:@current_buffer, buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)

    win = Rvim::Window.new(buf)
    win.row = 0; win.col = 0; win.width = 80; win.height = 11 # 10 content + 1 status
    win.scroll_top = 10 # viewport shows lines 10..19
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)
  end

  def test_H_jumps_to_top_visible_line
    @editor.instance_variable_set(:@line_index, 15)
    @editor.send(:rvim_window_top, nil)
    assert_equal 10, @editor.line_index
  end

  def test_H_lands_on_first_non_blank
    @editor.instance_variable_set(:@line_index, 15)
    @editor.send(:rvim_window_top, nil)
    # Each line is "  lineN" — first non-blank col is byte 2.
    assert_equal 2, @editor.byte_pointer
  end

  def test_L_jumps_to_bottom_visible_line
    @editor.instance_variable_set(:@line_index, 12)
    @editor.send(:rvim_window_bottom, nil)
    # scroll_top=10, content_rows=height-1=10, last visible = 19.
    assert_equal 19, @editor.line_index
  end

  def test_M_jumps_to_middle_visible_line
    @editor.instance_variable_set(:@line_index, 19)
    @editor.send(:rvim_window_middle, nil)
    # visible = 10..19, middle ~14
    assert_equal 14, @editor.line_index
  end

  def test_H_with_count_offsets_from_top
    @editor.instance_variable_set(:@line_index, 19)
    @editor.send(:rvim_window_top, nil, arg: 3)
    # 3H = 3rd line from top of viewport (top is 1st).
    assert_equal 12, @editor.line_index
  end

  def test_L_with_count_offsets_from_bottom
    @editor.instance_variable_set(:@line_index, 10)
    @editor.send(:rvim_window_bottom, nil, arg: 3)
    # 3L = 3rd line from bottom = 17.
    assert_equal 17, @editor.line_index
  end

  def test_M_ignores_count
    @editor.instance_variable_set(:@line_index, 19)
    @editor.send(:rvim_window_middle, nil, arg: 5)
    assert_equal 14, @editor.line_index
  end

  def test_H_clamps_to_buffer_size
    # If the buffer is shorter than the viewport, last visible line
    # clamps to buffer size - 1.
    @editor.buffer_of_lines.replace((0..3).map { |i| "  line#{i}" })
    @editor.instance_variable_set(:@line_index, 3)
    @editor.current_window.scroll_top = 0
    @editor.send(:rvim_window_bottom, nil)
    assert_equal 3, @editor.line_index
  end

  def test_count_clamps_within_visible_range
    @editor.instance_variable_set(:@line_index, 10)
    @editor.send(:rvim_window_top, nil, arg: 99) # 99H — way past bottom
    assert_equal 19, @editor.line_index
  end

  def test_H_pushes_jump_so_ctrl_o_returns
    @editor.instance_variable_set(:@line_index, 15)
    pre_byte = @editor.byte_pointer
    @editor.send(:rvim_window_top, nil)
    refute_empty @editor.jump_list, 'expected previous position pushed'
    assert_equal [15, pre_byte], @editor.jump_list.last
  end

  def test_no_op_when_already_at_target
    @editor.instance_variable_set(:@line_index, 10)
    @editor.send(:rvim_window_top, nil)
    assert_empty @editor.jump_list, 'no jump push when cursor was already there'
  end
end
