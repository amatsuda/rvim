# frozen_string_literal: true

require_relative 'test_helper'

class TestDisplayMotionAlgo < Test::Unit::TestCase
  # Trivial byte-based splitter (matches our screen logic for ASCII only).
  def split_ascii(line, width)
    return [[0, line]] if line.bytesize <= width

    out = []
    offset = 0
    while offset < line.bytesize
      seg = line.byteslice(offset, width)
      out << [offset, seg]
      offset += seg.bytesize
    end
    out
  end

  def step(lines, li, bp, width, dir)
    Rvim::DisplayMotion.next_position(
      lines, li, bp, width, dir, splitter: method(:split_ascii),
    )
  end

  def test_down_within_same_wrapped_line
    long = 'A' * 30
    # Width 10 splits into 3 segments at byte_off 0, 10, 20
    assert_equal [0, 12], step([long], 0, 2, 10, :down)
    assert_equal [0, 22], step([long], 0, 12, 10, :down)
  end

  def test_down_off_last_segment_to_next_line
    long = 'A' * 25
    # In segment 2 (byte_off 20) at byte 22 → moves to next line
    assert_equal [1, 2], step([long, 'B' * 5], 0, 22, 10, :down)
  end

  def test_up_within_same_wrapped_line
    long = 'A' * 30
    # From segment 1 byte 15 → segment 0 same line at offset 5
    assert_equal [0, 5], step([long], 0, 15, 10, :up)
    # From segment 0 byte 5 → no prev line in this single-line buffer → nil
    assert_nil step([long], 0, 5, 10, :up)
  end

  def test_up_off_first_segment_to_prev_line
    line0 = 'A' * 25
    line1 = 'B' * 30
    # On line 1 segment 0 byte 3 → moves to last segment of line 0 (which is segment 2 byte_off 20)
    assert_equal [0, 23], step([line0, line1], 1, 3, 10, :up)
  end

  def test_clamps_to_segment_size
    # Source segment has byte_in_seg=8 but target is short
    short_then_long = ['ab', 'A' * 30]
    # Down from line 0 byte 1 → target line 1 segment 0 (10 chars), keep byte_in_seg=1
    assert_equal [1, 1], step(short_then_long, 0, 1, 10, :down)
  end

  def test_returns_nil_at_buffer_top
    short = ['ab']
    assert_nil step(short, 0, 0, 10, :up)
  end

  def test_returns_nil_at_buffer_bottom
    short = ['ab']
    assert_nil step(short, 0, 1, 10, :down)
  end

  def test_zero_width_returns_nil
    assert_nil step(['hello'], 0, 0, 0, :down)
  end
end

class TestDisplayMotionDispatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def fire_g(letter)
    @editor.send(:rvim_g_prefix, nil, arg: nil)
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
  end

  def test_gj_without_screen_falls_through_to_j
    @editor.instance_variable_set(:@buffer_of_lines, %w[alpha beta gamma])
    @editor.instance_variable_set(:@line_index, 0)
    fire_g('j')
    assert_equal 1, @editor.line_index
  end

  def test_gk_without_screen_falls_through_to_k
    @editor.instance_variable_set(:@buffer_of_lines, %w[alpha beta gamma])
    @editor.instance_variable_set(:@line_index, 2)
    fire_g('k')
    assert_equal 1, @editor.line_index
  end

  def test_gj_at_eof_no_op
    @editor.instance_variable_set(:@buffer_of_lines, %w[only])
    @editor.instance_variable_set(:@line_index, 0)
    fire_g('j')
    assert_equal 0, @editor.line_index
  end

  def test_gk_at_top_no_op
    @editor.instance_variable_set(:@buffer_of_lines, %w[only])
    @editor.instance_variable_set(:@line_index, 0)
    fire_g('k')
    assert_equal 0, @editor.line_index
  end

  def test_gj_with_wrap_walks_within_long_line
    long = 'A' * 30
    @editor.instance_variable_set(:@buffer_of_lines, [+long, +'next'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.settings.set(:wrap, true)

    # Wire up a minimal screen + window so content_width is non-zero
    buf = Rvim::Buffer.new(1, nil); buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf); win.height = 25; win.width = 12
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)
    screen = Rvim::Screen.new(@editor)
    @editor.instance_variable_set(:@screen, screen)

    fire_g('j')
    # We're still on the same physical line — gj walked within the wrap
    assert_equal 0, @editor.line_index
    assert @editor.byte_pointer > 2
  end
end
