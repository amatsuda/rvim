# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestLuaApiExtended < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_list_bufs
    Tempfile.create('lua-api') do |f|
      @editor.open(f.path)
    end
    res = @editor.lua.eval('return vim.api.nvim_list_bufs()')
    assert_operator res.to_h.values.size, :>=, 1
  end

  def test_buf_is_valid
    Tempfile.create('lua-api') do |f|
      @editor.open(f.path)
    end
    bufnr = @editor.lua.eval('return vim.api.nvim_get_current_buf()').to_i
    assert_equal true, @editor.lua.eval("return vim.api.nvim_buf_is_valid(#{bufnr})")
    assert_equal false, @editor.lua.eval('return vim.api.nvim_buf_is_valid(99999)')
  end

  def test_buf_var_round_trip
    Tempfile.create('lua-api') do |f|
      @editor.open(f.path)
    end
    @editor.lua.eval('vim.api.nvim_buf_set_var(0, "tag", "ruby")')
    assert_equal 'ruby', @editor.lua.eval('return vim.api.nvim_buf_get_var(0, "tag")')
    @editor.lua.eval('vim.api.nvim_buf_del_var(0, "tag")')
    assert_nil @editor.lua.eval('return vim.api.nvim_buf_get_var(0, "tag")')
  end

  def test_global_var_round_trip
    @editor.lua.eval('vim.api.nvim_set_var("hello", "world")')
    assert_equal 'world', @editor.lua.eval('return vim.api.nvim_get_var("hello")')
    @editor.lua.eval('vim.api.nvim_del_var("hello")')
    assert_nil @editor.lua.eval('return vim.api.nvim_get_var("hello")')
  end

  def test_get_set_option
    @editor.lua.eval('vim.api.nvim_set_option("tabstop", 4)')
    assert_equal 4, @editor.lua.eval('return vim.api.nvim_get_option("tabstop")').to_i
  end

  def test_get_option_value_with_buf
    Tempfile.create('lua-api') do |f|
      @editor.open(f.path)
    end
    @editor.settings.set(:tabstop, 6, buffer: @editor.current_buffer)
    val = @editor.lua.eval('return vim.api.nvim_get_option_value("tabstop", { buf = 0 })').to_i
    assert_equal 6, val
  end

  def test_get_mode
    res = @editor.lua.eval('return vim.api.nvim_get_mode()')
    h = res.to_h
    assert_equal 'n', h['mode']
    assert_equal false, h['blocking']
  end

  def test_command
    @editor.lua.eval('vim.api.nvim_command("set ts=18")')
    assert_equal 18, @editor.settings.get(:tabstop)
  end

  def test_err_writeln
    @editor.lua.eval('vim.api.nvim_err_writeln("oops")')
    assert_match(/ERR: oops/, @editor.status_message.to_s)
  end

  def test_out_write
    @editor.lua.eval('vim.api.nvim_out_write("hi")')
    assert_equal 'hi', @editor.status_message.to_s
  end

  def test_strwidth
    assert_equal 5, @editor.lua.eval('return vim.api.nvim_strwidth("hello")').to_i
  end

  def test_replace_termcodes
    res = @editor.lua.eval('return vim.api.nvim_replace_termcodes("<CR>", true, true, true)')
    assert_equal "\r", res
  end

  def test_set_hl_remembers_name
    @editor.lua.eval('vim.api.nvim_set_hl(0, "MyHL", { fg = "red" })')
    refute_nil @editor.instance_variable_get(:@lua_highlights)
    assert @editor.instance_variable_get(:@lua_highlights)['MyHL']
  end

  def test_list_wins_returns_array
    res = @editor.lua.eval('return vim.api.nvim_list_wins()')
    assert_kind_of Hash, res.to_h # Lua array is hash with numeric keys
  end
end
