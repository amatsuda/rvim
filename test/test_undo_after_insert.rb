# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

# Regression: typing in insert mode and then pressing 'u' in normal mode
# would replace @buffer_of_lines but leave current_buffer.lines pointing
# at the (still mutated) old array — so the screen, which reads from
# current_buffer.lines, kept showing the typed character.
class TestUndoAfterInsert < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    Tempfile.create('rvim-undo') do |f|
      f.write("hello\n")
      f.close
      @editor.open(f.path)
    end
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_insert_then_undo_restores_buffer_lines
    @editor.config.editing_mode = :vi_insert
    send_keys('X') # types X at start of "hello"
    @editor.config.editing_mode = :vi_command
    assert_equal 'Xhello', @editor.buffer_of_lines[0]

    send_keys('u')
    assert_equal 'hello', @editor.buffer_of_lines[0]
    # Critical: the buffer struct's lines must agree with @buffer_of_lines,
    # because the screen renders from current_buffer.lines.
    assert_equal 'hello', @editor.current_buffer.lines[0]
    assert_same @editor.buffer_of_lines, @editor.current_buffer.lines
  end

  def test_insert_then_undo_then_redo
    @editor.config.editing_mode = :vi_insert
    send_keys('A')
    @editor.config.editing_mode = :vi_command
    send_keys('u')
    assert_equal 'hello', @editor.buffer_of_lines[0]
    assert_equal 'hello', @editor.current_buffer.lines[0]

    # Ctrl-R = redo (0x12)
    sym = @editor.send(:synthesize_key, 0x12.chr).method_symbol
    @editor.update(Reline::Key.new(0x12.chr, sym, false))
    assert_equal 'Ahello', @editor.buffer_of_lines[0]
    assert_equal 'Ahello', @editor.current_buffer.lines[0]
  end

  def test_buffer_struct_stays_in_sync_after_replace_overwrite
    @editor.config.editing_mode = :vi_command
    send_keys('R')
    @editor.replace_overwrite_at_cursor('Z')
    @editor.config.editing_mode = :vi_command
    send_keys('u')
    assert_same @editor.buffer_of_lines, @editor.current_buffer.lines
  end
end
