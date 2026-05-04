# frozen_string_literal: true

require_relative 'test_helper'

# The ruler used to show byte_pointer + 1 as the column number, which
# diverges from the visible cell column whenever multibyte / wide chars
# precede the cursor on a line. Now the ruler shows both the byte col
# and the virtual (display) col when they differ.
class TestDisplayColumnMultibyte < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_display_column_ascii
    assert_equal 0, @screen.send(:display_column, 'hello', 0)
    assert_equal 3, @screen.send(:display_column, 'hello', 3)
    assert_equal 5, @screen.send(:display_column, 'hello', 5)
  end

  def test_display_column_japanese_two_cells_per_char
    line = +'あいう'
    # Each 'あ' is 3 bytes UTF-8 and 2 terminal cells wide.
    assert_equal 0, @screen.send(:display_column, line, 0)
    assert_equal 2, @screen.send(:display_column, line, 3) # past 'あ'
    assert_equal 4, @screen.send(:display_column, line, 6) # past 'あい'
    assert_equal 6, @screen.send(:display_column, line, 9) # past 'あいう'
  end

  def test_display_column_mixed
    line = +'aあb'
    assert_equal 1, @screen.send(:display_column, line, 1) # past 'a'
    assert_equal 3, @screen.send(:display_column, line, 4) # past 'aあ'
    assert_equal 4, @screen.send(:display_column, line, 5) # past 'aあb'
  end

  def test_display_column_snaps_mid_codepoint
    line = +'あ'
    # byte 1 is mid-codepoint; display_column should snap back to byte 0
    # and report 0 cells consumed (cursor is on 'あ', not past it).
    assert_equal 0, @screen.send(:display_column, line, 1)
    assert_equal 0, @screen.send(:display_column, line, 2)
  end

  def test_display_column_handles_invalid_bytes
    bad = String.new("a\xE3b", encoding: Encoding::UTF_8)
    assert_nothing_raised { @screen.send(:display_column, bad, 3) }
  end
end

class TestRulerMultibyteColumn < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    buf = Rvim::Buffer.new(1)
    buf.lines = [+'aあb']
    @editor.instance_variable_set(:@current_buffer, buf)
    @editor.instance_variable_set(:@buffer_of_lines, buf.lines)
    win = Rvim::Window.new(buf)
    win.height = 5
    win.width = 40
    @editor.instance_variable_set(:@current_window, win)
    @editor.instance_variable_set(:@windows, [win])
    @screen = Rvim::Screen.new(@editor)
  end

  def test_ruler_shows_byte_and_display_col_when_they_differ
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 4) # past 'aあ'
    label = @screen.send(:window_status, @editor.current_window, true)
    # byte col = 5, display col = 4 → expect "5-4"
    assert_match(/1,5-4\b/, label)
  end

  def test_ruler_shows_single_col_when_byte_equals_display
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 1) # past 'a'
    label = @screen.send(:window_status, @editor.current_window, true)
    # byte col 2, display col 2 → expect just "2"
    assert_match(/1,2\b/, label)
    refute_match(/1,2-/, label)
  end
end
