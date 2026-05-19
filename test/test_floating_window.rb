# frozen_string_literal: true

require_relative 'test_helper'

# Floating windows: detached from the tiling layout, user-positioned,
# optionally bordered. Plus the supporting nvim_create_buf scratch
# buffers and the Lua surface.

class TestFloatingWindow < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @buf = Rvim::Buffer.new(@editor.next_buffer_id_bump!, nil, scratch: true, listed: false)
    @buf.lines = %w[alpha beta gamma]
    @editor.register_buffer(@buf)
  end

  # ----- scratch buffers -----

  def test_scratch_buffer_has_buftype_nofile_and_no_filepath
    assert_equal 'nofile', @buf.buftype
    assert @buf.scratch?
    assert_nil @buf.filepath
    refute @buf.listed
  end

  # ----- editor open / close -----

  def test_open_floating_window_appends_to_floating_windows_and_focuses
    win = @editor.open_floating_window(@buf, enter: true,
                                        config: { row: 2, col: 3, width: 30, height: 8, border: :single })
    assert win.floating?
    assert_equal [win], @editor.floating_windows
    assert_equal win, @editor.current_window
    assert_equal :single, win.border
    assert_equal [2, 3, 30, 8], [win.row, win.col, win.width, win.height]
  end

  def test_open_with_enter_false_keeps_current_window
    prev = @editor.current_window
    @editor.open_floating_window(@buf, enter: false, config: { row: 0, col: 0, width: 10, height: 3 })
    assert_equal prev, @editor.current_window
  end

  def test_close_floating_window_removes_from_list
    win = @editor.open_floating_window(@buf, enter: false,
                                        config: { row: 0, col: 0, width: 5, height: 3 })
    @editor.close_floating_window(win)
    assert_empty @editor.floating_windows
  end

  def test_normalize_border_accepts_strings_symbols_and_bool
    [:single, 'single', true].each do |b|
      win = @editor.open_floating_window(@buf, enter: false,
                                          config: { row: 0, col: 0, width: 5, height: 3, border: b })
      assert_equal :single, win.border
      @editor.close_floating_window(win)
    end
    win = @editor.open_floating_window(@buf, enter: false,
                                        config: { row: 0, col: 0, width: 5, height: 3, border: 'none' })
    assert_equal :none, win.border
    @editor.close_floating_window(win)
    win = @editor.open_floating_window(@buf, enter: false,
                                        config: { row: 0, col: 0, width: 5, height: 3, border: 'double' })
    assert_equal :double, win.border
  end

  def test_zindex_default_is_50
    win = @editor.open_floating_window(@buf, enter: false,
                                        config: { row: 0, col: 0, width: 5, height: 3 })
    assert_equal 50, win.zindex
  end

  def test_focus_window_swaps_buffer_state
    other = Rvim::Buffer.new(@editor.next_buffer_id_bump!, nil, scratch: true)
    other.lines = ['x']
    @editor.register_buffer(other)
    win = @editor.open_floating_window(other, enter: true,
                                        config: { row: 0, col: 0, width: 5, height: 3 })
    assert_equal other, @editor.current_buffer
    assert_equal win, @editor.current_window
  end

  # ----- rendering -----

  def test_render_emits_a_border_when_set
    screen = Rvim::Screen.new(@editor)
    @editor.open_floating_window(@buf, enter: false,
                                  config: { row: 5, col: 10, width: 15, height: 5, border: :single })
    out = screen.send(:render_floating_window, @editor.floating_windows.first)
    # Top-left corner at row 6 col 11 (move_to is 1-based).
    assert_match(/\e\[6;11H┌/, out)
    assert_match(/┐/, out)
    assert_match(/└/, out)
    assert_match(/┘/, out)
  end

  def test_render_inlines_title_into_top_border
    screen = Rvim::Screen.new(@editor)
    win = @editor.open_floating_window(@buf, enter: false,
                                        config: { row: 0, col: 0, width: 20, height: 5, border: :single,
                                                  title: 'Hello' })
    out = screen.send(:render_floating_window, win)
    assert_match(/Hello/, out)
  end

  def test_render_without_border_skips_box_drawing
    screen = Rvim::Screen.new(@editor)
    win = @editor.open_floating_window(@buf, enter: false,
                                        config: { row: 0, col: 0, width: 10, height: 3, border: :none })
    out = screen.send(:render_floating_window, win)
    refute_match(/┌|─|│/, out)
  end

  def test_hidden_floats_are_skipped_in_render
    win = @editor.open_floating_window(@buf, enter: false,
                                        config: { row: 0, col: 0, width: 10, height: 3, hide: true })
    assert win.hide
  end
end

class TestLuaFloatingWindow < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_nvim_create_buf_returns_an_id
    bufnr = @editor.lua.eval(<<~LUA).to_i
      return vim.api.nvim_create_buf(false, true)
    LUA
    assert_operator bufnr, :>, 0
    buf = @editor.buffers[bufnr]
    refute_nil buf
    assert buf.scratch?
    refute buf.listed
  end

  def test_nvim_open_win_returns_a_winid_and_registers_the_float
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      winid = vim.api.nvim_open_win(buf, true, { relative='editor', row=2, col=5, width=20, height=6, border='single' })
    LUA
    winid = @editor.lua.eval('return winid').to_i
    assert_operator winid, :>, 0
    assert_equal 1, @editor.floating_windows.size
    assert_equal winid, @editor.floating_windows.first.id
  end

  def test_nvim_win_get_config_returns_the_open_config
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      winid = vim.api.nvim_open_win(buf, false, { relative='editor', row=1, col=2, width=3, height=4, border='rounded' })
      cfg = vim.api.nvim_win_get_config(winid)
    LUA
    assert_equal 1, @editor.lua.eval('return cfg.row').to_i
    assert_equal 2, @editor.lua.eval('return cfg.col').to_i
    assert_equal 3, @editor.lua.eval('return cfg.width').to_i
    assert_equal 4, @editor.lua.eval('return cfg.height').to_i
    assert_equal 'rounded', @editor.lua.eval('return cfg.border')
  end

  def test_nvim_win_close_drops_the_float
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      winid = vim.api.nvim_open_win(buf, true, { row=0, col=0, width=5, height=3 })
      vim.api.nvim_win_close(winid, true)
    LUA
    assert_empty @editor.floating_windows
  end

  def test_nvim_win_set_config_resizes_the_float
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      winid = vim.api.nvim_open_win(buf, false, { row=0, col=0, width=5, height=3 })
      vim.api.nvim_win_set_config(winid, { row=10, col=20, width=40, height=12 })
    LUA
    win = @editor.floating_windows.first
    assert_equal 10, win.row
    assert_equal 20, win.col
    assert_equal 40, win.width
    assert_equal 12, win.height
  end
end
