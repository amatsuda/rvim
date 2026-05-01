# frozen_string_literal: true

require_relative 'test_helper'

class TestBlockInsert < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'one', +'two', +'three'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.config.editing_mode = :vi_command
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_block_I_then_type_then_esc_inserts_into_all_lines
    # Ctrl-V to enter visual block
    send_keys(0x16.chr)
    # j j to extend selection down two lines
    send_keys('j', 'j')
    # I to enter block insert at column 0
    send_keys('I')
    assert_equal :vi_insert, @editor.editing_mode_label
    refute_nil @editor.block_insert_state

    # Type "X " then leave insert mode
    @editor.insert_at_cursor('X ')
    @editor.config.editing_mode = :vi_command
    @editor.send(:capture_special_marks, [], :vi_insert)

    assert_equal 'X one', @editor.buffer_of_lines[0]
    assert_equal 'X two', @editor.buffer_of_lines[1]
    assert_equal 'X three', @editor.buffer_of_lines[2]
    assert_nil @editor.block_insert_state
  end

  def test_block_A_appends_after_rightmost_block_col
    # Position the selection to span cols 0..1 on rows 0..2.
    send_keys(0x16.chr)
    send_keys('j', 'j', 'l')
    send_keys('A')
    assert_equal :vi_insert, @editor.editing_mode_label

    @editor.insert_at_cursor('!')
    @editor.config.editing_mode = :vi_command
    @editor.send(:capture_special_marks, [], :vi_insert)

    # Block end col=1 → A inserts at col 2 on each line.
    assert_equal 'on!e',  @editor.buffer_of_lines[0]
    assert_equal 'tw!o',  @editor.buffer_of_lines[1]
    assert_equal 'th!ree', @editor.buffer_of_lines[2]
  end

  def test_block_I_only_one_line_acts_like_normal_I
    # Ctrl-V then immediately I — single-line block.
    send_keys(0x16.chr)
    send_keys('I')
    @editor.insert_at_cursor('Z')
    @editor.config.editing_mode = :vi_command
    @editor.send(:capture_special_marks, [], :vi_insert)

    assert_equal 'Zone', @editor.buffer_of_lines[0]
    # Other lines untouched.
    assert_equal 'two', @editor.buffer_of_lines[1]
  end

  def test_visual_line_I_moves_cursor_to_first_line_sol
    send_keys('V', 'j')
    send_keys('I')
    assert_equal :vi_insert, @editor.editing_mode_label
    assert_equal 0, @editor.line_index
    assert_equal 0, @editor.byte_pointer
  end

  def test_block_insert_skips_when_no_text_typed
    send_keys(0x16.chr)
    send_keys('j', 'j')
    send_keys('I')
    # No text typed; immediate Esc.
    @editor.config.editing_mode = :vi_command
    @editor.send(:capture_special_marks, [], :vi_insert)
    assert_equal 'one', @editor.buffer_of_lines[0]
    assert_equal 'two', @editor.buffer_of_lines[1]
    assert_equal 'three', @editor.buffer_of_lines[2]
  end

  def test_block_insert_handles_short_lines
    @editor.instance_variable_set(:@buffer_of_lines, [+'aaaaa', +'bb', +'ccccc'])
    send_keys(0x16.chr)
    send_keys('j', 'j', 'l', 'l') # block on cols 0..2
    send_keys('I')
    @editor.insert_at_cursor('-')
    @editor.config.editing_mode = :vi_command
    @editor.send(:capture_special_marks, [], :vi_insert)

    assert_equal '-aaaaa', @editor.buffer_of_lines[0]
    assert_equal '-bb', @editor.buffer_of_lines[1]
    assert_equal '-ccccc', @editor.buffer_of_lines[2]
  end
end
