# frozen_string_literal: true

require_relative 'test_helper'

class TestIncrementDecrement < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def buffer(line, byte: 0)
    @editor.instance_variable_set(:@buffer_of_lines, [+line])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, byte)
  end

  def increment(arg: 1)
    @editor.send(:rvim_increment, nil, arg: arg)
  end

  def decrement(arg: 1)
    @editor.send(:rvim_decrement, nil, arg: arg)
  end

  def test_increment_on_digit
    buffer('count: 5', byte: 7)
    increment
    assert_equal 'count: 6', @editor.buffer_of_lines[0]
  end

  def test_decrement_on_digit
    buffer('count: 5', byte: 7)
    decrement
    assert_equal 'count: 4', @editor.buffer_of_lines[0]
  end

  def test_increment_scans_forward_to_next_number
    buffer('abc 5 def', byte: 0)
    increment
    assert_equal 'abc 6 def', @editor.buffer_of_lines[0]
  end

  def test_increment_no_number_no_change
    buffer('no number here', byte: 0)
    increment
    assert_equal 'no number here', @editor.buffer_of_lines[0]
  end

  def test_increment_walks_back_to_start_of_digit_run
    buffer('value=42', byte: 7) # cursor on '2'
    increment
    assert_equal 'value=43', @editor.buffer_of_lines[0]
  end

  def test_increment_handles_negative_number
    buffer('temp=-3', byte: 6) # cursor on '3'
    increment
    assert_equal 'temp=-2', @editor.buffer_of_lines[0]
  end

  def test_decrement_handles_negative_number
    buffer('temp=-3', byte: 6)
    decrement
    assert_equal 'temp=-4', @editor.buffer_of_lines[0]
  end

  def test_minus_after_word_char_is_not_part_of_number
    buffer('abc-3', byte: 4) # cursor on '3', preceded by 'c-' — c is word char so - is not sign
    increment
    assert_equal 'abc-4', @editor.buffer_of_lines[0]
  end

  def test_count_multiplies_increment
    buffer('x 1', byte: 2)
    increment(arg: 5)
    assert_equal 'x 6', @editor.buffer_of_lines[0]
  end

  def test_count_multiplies_decrement
    buffer('x 10', byte: 2)
    decrement(arg: 3)
    assert_equal 'x 7', @editor.buffer_of_lines[0]
  end

  def test_increment_crosses_zero
    buffer('x -1', byte: 3)
    increment
    assert_equal 'x 0', @editor.buffer_of_lines[0]
    decrement(arg: 2)
    assert_equal 'x -2', @editor.buffer_of_lines[0]
  end

  def test_cursor_lands_on_last_digit_of_new_number
    buffer('x 9', byte: 2)
    increment # 9 -> 10, two digits
    assert_equal 3, @editor.byte_pointer
    assert_equal '0', @editor.buffer_of_lines[0].byteslice(@editor.byte_pointer, 1)
  end

  def test_increment_marks_buffer_modified
    buffer('x 1', byte: 2)
    @editor.modified = false
    increment
    assert_equal true, @editor.modified
  end

  def test_no_change_does_not_mark_modified
    buffer('no digits', byte: 0)
    @editor.modified = false
    increment
    assert_equal false, @editor.modified
  end

  def test_empty_line_no_op
    buffer('', byte: 0)
    increment
    assert_equal '', @editor.buffer_of_lines[0]
  end

  def test_only_digit
    buffer('7', byte: 0)
    increment
    assert_equal '8', @editor.buffer_of_lines[0]
  end

  def test_multiple_numbers_picks_first_after_cursor
    buffer('a 3 b 5 c', byte: 4) # cursor between numbers, on ' '
    increment
    assert_equal 'a 3 b 6 c', @editor.buffer_of_lines[0]
  end
end
