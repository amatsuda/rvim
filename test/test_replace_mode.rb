# frozen_string_literal: true

require_relative 'test_helper'

class TestReplaceOne < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 1) # on 'e'
    @editor.config.editing_mode = :vi_command
  end

  def test_r_replaces_single_char
    @editor.send(:rvim_replace_one, nil)
    @editor.instance_variable_get(:@waiting_proc).call('a', nil)
    assert_equal 'hallo', @editor.buffer_of_lines[0]
  end

  def test_r_with_count_replaces_n_chars
    @editor.send(:rvim_replace_one, nil, arg: 3)
    @editor.instance_variable_get(:@waiting_proc).call('x', nil)
    assert_equal 'hxxxo', @editor.buffer_of_lines[0]
  end

  def test_r_esc_cancels
    @editor.send(:rvim_replace_one, nil)
    @editor.instance_variable_get(:@waiting_proc).call("\e", nil)
    assert_equal 'hello', @editor.buffer_of_lines[0]
  end

  def test_r_at_eol_does_not_extend
    @editor.instance_variable_set(:@byte_pointer, 5) # past 'o'
    @editor.send(:rvim_replace_one, nil)
    @editor.instance_variable_get(:@waiting_proc).call('z', nil)
    # Replacing past end leaves the line unchanged.
    assert_equal 'hello', @editor.buffer_of_lines[0]
  end
end

class TestReplaceMode < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
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

  def test_R_enters_replace_mode
    send_keys('R')
    assert_equal :vi_insert, @editor.editing_mode_label
    assert_equal true, @editor.replace_mode
  end

  def test_R_overwrites_chars
    send_keys('R')
    @editor.replace_overwrite_at_cursor('X')
    @editor.replace_overwrite_at_cursor('Y')
    @editor.replace_overwrite_at_cursor('Z')
    assert_equal 'XYZlo', @editor.buffer_of_lines[0]
  end

  def test_R_extends_past_eol
    @editor.instance_variable_set(:@byte_pointer, 5) # past 'o'
    send_keys('R')
    @editor.replace_overwrite_at_cursor('!')
    assert_equal 'hello!', @editor.buffer_of_lines[0]
  end

  def test_R_backspace_restores_original
    send_keys('R')
    @editor.replace_overwrite_at_cursor('X')
    @editor.replace_overwrite_at_cursor('Y')
    assert_equal 'XYllo', @editor.buffer_of_lines[0]
    @editor.replace_undo_at_cursor
    assert_equal 'Xello', @editor.buffer_of_lines[0]
    @editor.replace_undo_at_cursor
    assert_equal 'hello', @editor.buffer_of_lines[0]
  end

  def test_R_backspace_after_extend_truncates
    @editor.instance_variable_set(:@byte_pointer, 5) # past 'o'
    send_keys('R')
    @editor.replace_overwrite_at_cursor('!')
    assert_equal 'hello!', @editor.buffer_of_lines[0]
    @editor.replace_undo_at_cursor
    assert_equal 'hello', @editor.buffer_of_lines[0]
  end

  def test_esc_clears_replace_mode
    send_keys('R')
    assert_equal true, @editor.replace_mode
    @editor.config.editing_mode = :vi_command
    # Trigger the capture by sending any normal-mode key:
    @editor.send(:capture_special_marks, @editor.buffer_of_lines.map(&:dup), :vi_insert)
    assert_equal false, @editor.replace_mode
  end
end
