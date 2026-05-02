# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# Regression: pressing 'v' on a line containing multibyte characters used to
# raise "invalid byte sequence in UTF-8" because splice_highlight byteslice'd
# mid-character (end_col + 1 lands inside a 3-byte UTF-8 codepoint).
class TestVisualMultibyte < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'あいうえお'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.config.editing_mode = :vi_command
    buf = Rvim::Buffer.new(1)
    buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf)
    win.height = 5
    win.width = 40
    @editor.instance_variable_set(:@current_window, win)
    @editor.instance_variable_set(:@windows, [win])
    @screen = Rvim::Screen.new(@editor)
  end

  def test_splice_highlight_does_not_break_multibyte_char
    # Visual char at byte 0 wants to highlight bytes 0..0 (end_col + 1 = 1),
    # but byte 1 falls inside 'あ' (3-byte UTF-8). After the fix, the
    # highlighted run snaps to the next char boundary, byteslice returns
    # valid UTF-8, and visible_width succeeds.
    line = @editor.buffer_of_lines[0]
    out = @screen.send(:splice_highlight, line.dup, 0, 1, 40)
    assert out.valid_encoding?
    # visible_width must not raise on the result.
    assert_nothing_raised { @screen.send(:visible_width, out) }
  end

  def test_v_then_render_does_not_raise
    @editor.send(:enter_visual, :char)
    assert_nothing_raised do
      original = $stdout
      $stdout = StringIO.new
      begin
        @screen.render
      ensure
        $stdout = original
      end
    end
  end

  def test_visible_width_handles_invalid_bytes
    bad = String.new("abc\xE3def", encoding: Encoding::UTF_8)
    refute bad.valid_encoding?
    assert_nothing_raised { @screen.send(:visible_width, bad) }
  end

  def test_snap_to_char_boundary_aligns_inside_multibyte
    line = +'あいう'
    # Bytes:  0 1 2 | 3 4 5 | 6 7 8
    #         あ      い      う
    assert_equal 3, @screen.send(:snap_to_char_boundary, line, 1) # mid 'あ' → 'い' boundary
    assert_equal 3, @screen.send(:snap_to_char_boundary, line, 2)
    assert_equal 3, @screen.send(:snap_to_char_boundary, line, 3) # already aligned
    assert_equal 6, @screen.send(:snap_to_char_boundary, line, 5) # mid 'い' → 'う' boundary
    assert_equal 0, @screen.send(:snap_to_char_boundary, line, 0)
    assert_equal line.bytesize, @screen.send(:snap_to_char_boundary, line, line.bytesize)
  end
end
