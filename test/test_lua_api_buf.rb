# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestLuaApiBuf < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    Tempfile.create('lua-buf') do |f|
      f.write("a\nb\nc\nd\n")
      f.close
      @editor.open(f.path)
    end
  end

  def test_get_current_buf_returns_id
    id = @editor.lua.eval('return vim.api.nvim_get_current_buf()').to_i
    assert_equal @editor.current_buffer.id, id
  end

  def test_buf_line_count
    assert_operator @editor.lua.eval('return vim.api.nvim_buf_line_count(0)').to_i, :>=, 4
  end

  def test_buf_get_lines_full
    res = @editor.lua.eval('return vim.api.nvim_buf_get_lines(0, 0, -1, true)')
    lines = res.to_h.values
    assert_includes lines, 'a'
    assert_includes lines, 'd'
  end

  def test_buf_get_lines_slice
    res = @editor.lua.eval('return vim.api.nvim_buf_get_lines(0, 1, 3, true)')
    assert_equal({ 1.0 => 'b', 2.0 => 'c' }, res.to_h)
  end

  def test_buf_set_lines_replaces
    @editor.lua.eval('vim.api.nvim_buf_set_lines(0, 0, -1, true, {"x","y"})')
    assert_equal 'x', @editor.buffer_of_lines[0]
    assert_equal 'y', @editor.buffer_of_lines[1]
  end

  def test_buf_set_lines_inserts_at_offset
    @editor.lua.eval('vim.api.nvim_buf_set_lines(0, 1, 1, true, {"INSERT"})')
    assert_equal 'INSERT', @editor.buffer_of_lines[1]
  end

  def test_buf_get_name
    name = @editor.lua.eval('return vim.api.nvim_buf_get_name(0)')
    assert_equal @editor.current_buffer.filepath.to_s, name.to_s
  end

  def test_buf_get_option
    @editor.settings.set(:tabstop, 4, buffer: @editor.current_buffer)
    val = @editor.lua.eval('return vim.api.nvim_buf_get_option(0, "tabstop")').to_i
    assert_equal 4, val
  end

  def test_buf_set_option
    @editor.lua.eval('vim.api.nvim_buf_set_option(0, "tabstop", 6)')
    assert_equal 6, @editor.current_buffer.local_settings[:tabstop]
  end

  def test_buf_set_lines_negative_indexes
    @editor.lua.eval('vim.api.nvim_buf_set_lines(0, -1, -1, true, {"appended"})')
    assert_equal 'appended', @editor.buffer_of_lines.last
  end
end
