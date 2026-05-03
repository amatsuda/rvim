# frozen_string_literal: true

require_relative 'test_helper'

# Regression: vertical motion (gj/gk via display motion, or plain line
# step) clamped byte_pointer to bytesize-1 of the target line. When the
# target was a multibyte char like 'あ', clamping landed mid-codepoint
# and Reline's wrapped_cursor_position raised on the next render.
class TestDisplayMotionMultibyte < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'aあ', +'あ'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 1)
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

  def test_gj_to_multibyte_line_does_not_crash
    assert_nothing_raised { send_keys('g', 'j') }
    assert_equal 1, @editor.line_index
    assert_equal 0, @editor.byte_pointer
    assert @editor.buffer_of_lines[@editor.line_index].valid_encoding?
  end

  def test_gk_to_multibyte_line_does_not_crash
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 0)
    assert_nothing_raised { send_keys('g', 'k') }
    # Cursor must land on a char boundary on line 0 ("aあ").
    bp = @editor.byte_pointer
    line = @editor.buffer_of_lines[0]
    assert(bp == 0 || bp == 1, "expected cursor on byte 0 or 1, got #{bp}")
    assert line.byteslice(0, bp).valid_encoding?
  end

  def test_snap_back_to_char_boundary_helper
    line = +'あいう'
    # Continuation bytes at 1, 2 (mid-'あ'); leading at 0, 3, 6.
    assert_equal 0, Rvim::DisplayMotion.snap_back_to_char_boundary(line, 1)
    assert_equal 0, Rvim::DisplayMotion.snap_back_to_char_boundary(line, 2)
    assert_equal 3, Rvim::DisplayMotion.snap_back_to_char_boundary(line, 4)
    assert_equal 3, Rvim::DisplayMotion.snap_back_to_char_boundary(line, 5)
    assert_equal 3, Rvim::DisplayMotion.snap_back_to_char_boundary(line, 3)
    assert_equal 0, Rvim::DisplayMotion.snap_back_to_char_boundary(line, 0)
  end

  def test_plain_line_step_also_snaps_back
    # Force the non-display path by flipping wrap off.
    @editor.settings.set(:wrap, false)
    # Set a high desired byte that on the multibyte target lands mid-char.
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.send(:plain_line_step, :down)
    line = @editor.buffer_of_lines[@editor.line_index]
    assert line.byteslice(0, @editor.byte_pointer).valid_encoding?
  end
end
