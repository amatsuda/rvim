# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaApiWin < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    buf = Rvim::Buffer.new(1)
    buf.lines = [+'one', +'two', +'three']
    @editor.instance_variable_set(:@buffer_of_lines, buf.lines)
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

  def test_win_set_cursor_on_non_current_window_does_not_touch_editor_state
    # Regression: telescope opens a floating prompt window during
    # setup and calls nvim_win_set_cursor on it. The shim used to
    # write directly to the editor's @line_index / @byte_pointer,
    # clobbering the cursor of the still-current buffer ([No Name]).
    # A subsequent `i` + char then crashed in Reline's byteinsert
    # because byte_pointer was past the line's end.
    other_buf = Rvim::Buffer.new(99)
    other_buf.lines = [+'']
    other_win = Rvim::Window.new(other_buf)
    other_win.floating = true
    @editor.floating_windows << other_win
    other_win_id = other_win.id

    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)

    @editor.lua.eval("vim.api.nvim_win_set_cursor(#{other_win_id}, {1, 5})")

    # Editor globals untouched — still pointing at [No Name].
    assert_equal 0, @editor.line_index
    assert_equal 0, @editor.byte_pointer
    # The float's buffer remembers the requested cursor (clamped to
    # its empty single line — col 5 → col 0).
    assert_equal 0, other_buf.line_index
    assert_equal 0, other_buf.byte_pointer
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

  def test_get_current_win_returns_a_stable_id
    # NeoVim's win-ids aren't 1-based indices — they're stable
    # handles. We allocate one per Window via Window.allocate_id;
    # the only invariant for an existing window is that it's > 0.
    n = @editor.lua.eval('return vim.api.nvim_get_current_win()').to_i
    assert_operator n, :>, 0
  end
end
