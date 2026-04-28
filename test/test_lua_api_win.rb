# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaApiWin < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    @editor.instance_variable_set(:@buffer_of_lines, [+'one', +'two', +'three'])
    buf = Rvim::Buffer.new(1)
    win = Rvim::Window.new(buf)
    @editor.instance_variable_set(:@current_window, win)
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_buffer, buf)
  end

  def test_win_get_cursor_returns_one_based_row
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    res = @editor.lua.eval('return vim.api.nvim_win_get_cursor(0)')
    arr = res.to_h.values
    assert_equal 2, arr[0].to_i # row 1-based
    assert_equal 2, arr[1].to_i # col 0-based
  end

  def test_win_set_cursor_moves_cursor
    @editor.lua.eval('vim.api.nvim_win_set_cursor(0, {3, 1})')
    assert_equal 2, @editor.line_index # zero-indexed: row 3 → idx 2
    assert_equal 1, @editor.byte_pointer
  end

  def test_win_set_cursor_clamps_to_buffer
    @editor.lua.eval('vim.api.nvim_win_set_cursor(0, {999, 0})')
    assert_equal 2, @editor.line_index # last line index
  end

  def test_win_get_height
    h = @editor.lua.eval('return vim.api.nvim_win_get_height(0)').to_i
    assert_operator h, :>, 0
  end

  def test_win_set_height
    @editor.lua.eval('vim.api.nvim_win_set_height(0, 10)')
    assert_equal 10, @editor.current_window&.height
  end

  def test_win_get_width
    w = @editor.lua.eval('return vim.api.nvim_win_get_width(0)').to_i
    assert_operator w, :>, 0
  end

  def test_win_get_buf
    bufid = @editor.lua.eval('return vim.api.nvim_win_get_buf(0)').to_i
    assert_equal (@editor.current_buffer&.id || 0), bufid
  end

  def test_get_current_win_returns_one_based
    n = @editor.lua.eval('return vim.api.nvim_get_current_win()').to_i
    assert_equal 1, n
  end
end
