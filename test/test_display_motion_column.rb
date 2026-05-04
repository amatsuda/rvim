# frozen_string_literal: true

require_relative 'test_helper'

# Display motion (gj/gk, and j/k under :set wrap) should preserve the
# cursor's *display column* across lines, not its byte offset. Without
# this, moving from "1234567890" col 2 onto "あいうえお" landed on 'あ'
# (byte 2 = mid-codepoint, snapped to byte 0) instead of 'い' (byte 3,
# the char that occupies display col 2).
class TestDisplayMotionColumn < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'1234567890', +'あいうえお'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
    buf = Rvim::Buffer.new(1)
    buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf)
    win.height = 5
    win.width = 40
    @editor.instance_variable_set(:@current_window, win)
    @editor.instance_variable_set(:@windows, [win])
    @editor.screen = Rvim::Screen.new(@editor)
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_gj_from_ascii_col_2_lands_on_い
    send_keys('g', 'j')
    assert_equal 1, @editor.line_index
    # 'い' starts at byte 3 of "あいうえお".
    assert_equal 3, @editor.byte_pointer
  end

  def test_gj_from_ascii_col_4_lands_on_う
    @editor.instance_variable_set(:@byte_pointer, 4) # on '5', display col 4
    send_keys('g', 'j')
    # 'う' (display cols 4-5) starts at byte 6.
    assert_equal 6, @editor.byte_pointer
  end

  def test_gk_back_from_japanese_to_ascii_preserves_col
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 3) # on 'い' = display col 2
    send_keys('g', 'k')
    assert_equal 0, @editor.line_index
    assert_equal 2, @editor.byte_pointer # '3' on the ASCII line
  end

  def test_gj_from_long_ascii_to_short_japanese_clamps
    @editor.instance_variable_set(:@buffer_of_lines, [+'1234567890', +'あ'])
    @editor.instance_variable_set(:@byte_pointer, 5) # on '6', display col 5
    send_keys('g', 'j')
    # 'あ' is the only char (display cols 0-1); cursor lands on it (byte 0).
    assert_equal 0, @editor.byte_pointer
  end

  def test_byte_at_display_column_helper
    line = +'あいうえお'
    assert_equal 0, Rvim::DisplayMotion.byte_at_display_column(line, 0)
    assert_equal 0, Rvim::DisplayMotion.byte_at_display_column(line, 1) # mid-'あ'
    assert_equal 3, Rvim::DisplayMotion.byte_at_display_column(line, 2) # 'い'
    assert_equal 3, Rvim::DisplayMotion.byte_at_display_column(line, 3) # mid-'い'
    assert_equal 6, Rvim::DisplayMotion.byte_at_display_column(line, 4) # 'う'
  end

  def test_display_column_in_helper
    line = +'aあb'
    assert_equal 0, Rvim::DisplayMotion.display_column_in(line, 0)
    assert_equal 1, Rvim::DisplayMotion.display_column_in(line, 1) # past 'a'
    assert_equal 3, Rvim::DisplayMotion.display_column_in(line, 4) # past 'aあ'
  end
end
