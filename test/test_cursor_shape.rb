# frozen_string_literal: true

require_relative 'test_helper'

class TestCursorShape < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_normal_mode_uses_block
    @editor.config.editing_mode = :vi_command
    assert_equal Rvim::Screen::CURSOR_BLOCK, @screen.cursor_shape_for_mode
  end

  def test_insert_mode_uses_vertical_bar
    @editor.config.editing_mode = :vi_insert
    assert_equal Rvim::Screen::CURSOR_BAR, @screen.cursor_shape_for_mode
  end

  def test_replace_mode_uses_underline
    @editor.config.editing_mode = :vi_insert
    @editor.instance_variable_set(:@replace_mode, true)
    assert_equal Rvim::Screen::CURSOR_UNDERLINE, @screen.cursor_shape_for_mode
  end

  def test_cmdline_prompt_uses_vertical_bar
    @editor.config.editing_mode = :vi_command
    @editor.instance_variable_set(:@prompt_mode, :ex)
    assert_equal Rvim::Screen::CURSOR_BAR, @screen.cursor_shape_for_mode
  end

  def test_cursor_bar_is_decscusr_six
    assert_equal "\e[6 q", Rvim::Screen::CURSOR_BAR
  end

  def test_cursor_block_is_decscusr_two
    assert_equal "\e[2 q", Rvim::Screen::CURSOR_BLOCK
  end

  def test_cursor_underline_is_decscusr_four
    assert_equal "\e[4 q", Rvim::Screen::CURSOR_UNDERLINE
  end
end
