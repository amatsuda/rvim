# frozen_string_literal: true

require_relative 'test_helper'

# Arrow keys move the cursor in both insert and command modes —
# Reline's default keymap doesn't bind them so without these
# explicit handlers the `\e` in `\e[A` would exit insert mode and
# the rest of the sequence would dangle in command mode.

class TestArrowKeys < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello', +'world', +'foo'])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.config.editing_mode = :vi_insert
  end

  def test_left_moves_one_column_back
    @editor.send(:rvim_arrow_left, nil)
    assert_equal 1, @editor.byte_pointer
    assert_equal 1, @editor.line_index
  end

  def test_left_at_column_zero_is_no_op
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:rvim_arrow_left, nil)
    assert_equal 0, @editor.byte_pointer
  end

  def test_right_moves_one_column_forward
    @editor.send(:rvim_arrow_right, nil)
    assert_equal 3, @editor.byte_pointer
  end

  def test_insert_mode_right_can_land_past_last_char
    # Buffer "world" is 5 bytes. In insert mode the cursor can sit
    # at byte 5 (past last char).
    @editor.instance_variable_set(:@byte_pointer, 5)
    @editor.send(:rvim_arrow_right, nil)
    assert_equal 5, @editor.byte_pointer, 'clamped at end of line'
  end

  def test_command_mode_right_clamps_onto_last_char
    @editor.config.editing_mode = :vi_command
    @editor.instance_variable_set(:@byte_pointer, 4) # on `d` of `world`
    @editor.send(:rvim_arrow_right, nil)
    assert_equal 4, @editor.byte_pointer, 'cursor can only sit ON a char, not past'
  end

  def test_up_moves_to_previous_line_preserving_column
    @editor.send(:rvim_arrow_up, nil)
    assert_equal 0, @editor.line_index
    assert_equal 2, @editor.byte_pointer
  end

  def test_up_at_first_line_is_no_op
    @editor.instance_variable_set(:@line_index, 0)
    @editor.send(:rvim_arrow_up, nil)
    assert_equal 0, @editor.line_index
  end

  def test_down_moves_to_next_line_preserving_column
    @editor.send(:rvim_arrow_down, nil)
    assert_equal 2, @editor.line_index
    assert_equal 2, @editor.byte_pointer
  end

  def test_down_clamps_column_for_shorter_target_line
    @editor.instance_variable_set(:@line_index, 0) # "hello"
    @editor.instance_variable_set(:@byte_pointer, 4)
    @editor.send(:rvim_arrow_down, nil) # → "world", same len
    @editor.send(:rvim_arrow_down, nil) # → "foo" (3 bytes)
    assert_equal 2, @editor.line_index
    # In insert mode max is bytesize (3); in command max is bytesize - 1.
    assert_operator @editor.byte_pointer, :<=, 3
  end

  def test_count_arg_advances_multiple_columns
    @editor.send(:rvim_arrow_right, nil, arg: 3)
    assert_equal 5, @editor.byte_pointer # 2 + 3
  end

  def test_left_walks_back_through_multibyte_char
    # "aあb": a(1) + あ(3) + b(1). Position 4 → step left → 1 (start of あ).
    @editor.buffer_of_lines[@editor.line_index] = +'aあb'
    @editor.instance_variable_set(:@byte_pointer, 4) # on 'b'
    @editor.send(:rvim_arrow_left, nil)
    assert_equal 1, @editor.byte_pointer, 'snaps to char boundary'
  end

  def test_right_walks_forward_through_multibyte_char
    @editor.buffer_of_lines[@editor.line_index] = +'aあb'
    @editor.instance_variable_set(:@byte_pointer, 1) # on 'あ'
    @editor.send(:rvim_arrow_right, nil)
    assert_equal 4, @editor.byte_pointer, 'jumps across 3-byte char'
  end

  def test_right_at_command_mode_end_of_line_with_multibyte_stays_on_last_char
    # "xあ" — command mode rightmost cursor must sit ON the start of
    # `あ` (byte 1), NOT inside its continuation bytes. Without the
    # last_char_start_byte clamp, Reline crashed walking width on
    # the torn UTF-8 sequence.
    @editor.config.editing_mode = :vi_command
    @editor.buffer_of_lines[@editor.line_index] = +'xあ'
    @editor.instance_variable_set(:@byte_pointer, 1) # on `あ`
    @editor.send(:rvim_arrow_right, nil)
    assert_equal 1, @editor.byte_pointer, 'no move past last char in command mode'
  end

  def test_right_in_insert_mode_can_advance_past_trailing_multibyte
    @editor.config.editing_mode = :vi_insert
    @editor.buffer_of_lines[@editor.line_index] = +'xあ'
    @editor.instance_variable_set(:@byte_pointer, 1) # on `あ`
    @editor.send(:rvim_arrow_right, nil)
    assert_equal 4, @editor.byte_pointer, 'past last char allowed in insert'
  end
end
