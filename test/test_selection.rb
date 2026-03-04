# frozen_string_literal: true

require_relative 'test_helper'

class TestSelection < Test::Unit::TestCase
  def setup
    @buf = ['hello world', 'second line', 'three', 'four', 'five']
  end

  # ---- charwise ----

  def test_char_anchor_before_cursor_same_line
    sel = Rvim::Selection.from(:char, [0, 2], [0, 6], @buf)
    assert_equal 0, sel.start_line
    assert_equal 2, sel.start_col
    assert_equal 0, sel.end_line
    assert_equal 6, sel.end_col
  end

  def test_char_anchor_after_cursor_swaps
    sel = Rvim::Selection.from(:char, [2, 4], [0, 1], @buf)
    assert_equal 0, sel.start_line
    assert_equal 1, sel.start_col
    assert_equal 2, sel.end_line
    assert_equal 4, sel.end_col
  end

  def test_char_includes_inclusive_endpoints
    sel = Rvim::Selection.from(:char, [0, 2], [0, 5], @buf)
    assert_equal false, sel.includes?(0, 1)
    assert_equal true, sel.includes?(0, 2)
    assert_equal true, sel.includes?(0, 5)
    assert_equal false, sel.includes?(0, 6)
  end

  def test_char_includes_multiline
    sel = Rvim::Selection.from(:char, [0, 6], [2, 1], @buf)
    assert_equal false, sel.includes?(0, 5)
    assert_equal true, sel.includes?(0, 6)
    assert_equal true, sel.includes?(0, 100) # past EOL on first line
    assert_equal true, sel.includes?(1, 0)   # full middle line
    assert_equal true, sel.includes?(2, 0)
    assert_equal true, sel.includes?(2, 1)
    assert_equal false, sel.includes?(2, 2)
    assert_equal false, sel.includes?(3, 0)
  end

  # ---- linewise ----

  def test_line_normalizes
    sel = Rvim::Selection.from(:line, [3, 999], [1, 0], @buf)
    assert_equal 1, sel.start_line
    assert_equal 3, sel.end_line
    assert sel.linewise?
  end

  def test_line_includes_full_rows_only
    sel = Rvim::Selection.from(:line, [1, 0], [2, 0], @buf)
    assert_equal false, sel.includes?(0, 0)
    assert_equal true, sel.includes?(1, 0)
    assert_equal true, sel.includes?(1, 999)
    assert_equal true, sel.includes?(2, 0)
    assert_equal false, sel.includes?(3, 0)
  end

  # ---- blockwise ----

  def test_block_top_left_to_bottom_right
    sel = Rvim::Selection.from(:block, [0, 1], [2, 4], @buf)
    assert_equal 0, sel.start_line
    assert_equal 2, sel.end_line
    assert_equal 1, sel.start_col
    assert_equal 4, sel.end_col
  end

  def test_block_bottom_right_to_top_left_normalizes
    sel = Rvim::Selection.from(:block, [2, 4], [0, 1], @buf)
    assert_equal 0, sel.start_line
    assert_equal 2, sel.end_line
    assert_equal 1, sel.start_col
    assert_equal 4, sel.end_col
  end

  def test_block_includes_rectangle
    sel = Rvim::Selection.from(:block, [0, 1], [2, 4], @buf)
    assert_equal true, sel.includes?(0, 1)
    assert_equal true, sel.includes?(0, 4)
    assert_equal true, sel.includes?(1, 2)
    assert_equal true, sel.includes?(2, 4)
    assert_equal false, sel.includes?(0, 0)
    assert_equal false, sel.includes?(0, 5)
    assert_equal false, sel.includes?(3, 1)
  end

  # ---- each_segment ----

  def test_each_segment_charwise_single_line
    sel = Rvim::Selection.from(:char, [0, 2], [0, 5], @buf)
    segs = []
    sel.each_segment(@buf) { |l, s, e| segs << [l, s, e] }
    assert_equal [[0, 2, 6]], segs # end is exclusive byte index
  end

  def test_each_segment_linewise
    sel = Rvim::Selection.from(:line, [1, 0], [2, 0], @buf)
    segs = []
    sel.each_segment(@buf) { |l, s, e| segs << [l, s, e] }
    assert_equal [[1, 0, @buf[1].bytesize], [2, 0, @buf[2].bytesize]], segs
  end

  def test_each_segment_blockwise_clamps_to_line
    short = ['abcdefgh', 'ab', 'abcd']
    sel = Rvim::Selection.from(:block, [0, 2], [2, 5], short)
    segs = []
    sel.each_segment(short) { |l, s, e| segs << [l, s, e] }
    assert_equal [[0, 2, 6], [1, 2, 2], [2, 2, 4]], segs
  end
end
