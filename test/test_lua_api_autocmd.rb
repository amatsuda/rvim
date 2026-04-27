# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaApiAutocmd < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_create_augroup_returns_id
    id = @editor.lua.eval(<<~LUA)
      return vim.api.nvim_create_augroup("MyGroup", { clear = true })
    LUA
    assert_kind_of Numeric, id
    assert_operator id.to_i, :>, 0
  end

  def test_create_autocmd_with_command
    @editor.lua.eval(<<~LUA)
      vim.api.nvim_create_autocmd("BufRead", {
        pattern = "*.foo",
        command = "set ts=8",
      })
    LUA
    assert_equal 1, @editor.autocommands.size
  end

  def test_create_autocmd_with_callback_fires
    @editor.lua.eval(<<~LUA)
      vim.g.fired = 0
      vim.api.nvim_create_autocmd("BufRead", {
        pattern = "*.lua",
        callback = function(args) vim.g.fired = 1 end,
      })
    LUA
    @editor.autocommands.fire(:bufread, '/tmp/x.lua', @editor)
    assert_equal 1, @editor.let_vars['fired'].to_i
  end

  def test_create_autocmd_grouped
    @editor.lua.eval(<<~LUA)
      local g = vim.api.nvim_create_augroup("Test", { clear = true })
      vim.api.nvim_create_autocmd("BufRead", {
        group = g,
        pattern = "*",
        command = "set ts=2",
      })
    LUA
    assert_equal 1, @editor.autocommands.size
  end

  def test_del_augroup_by_name_clears_entries
    @editor.lua.eval(<<~LUA)
      vim.api.nvim_create_augroup("ToRemove", { clear = true })
      vim.api.nvim_create_autocmd("BufRead", {
        group = "ToRemove",
        pattern = "*",
        command = "set ts=2",
      })
      vim.api.nvim_del_augroup_by_name("ToRemove")
    LUA
    assert_equal 0, @editor.autocommands.size
  end

  def test_create_autocmd_multiple_events
    @editor.lua.eval(<<~LUA)
      vim.api.nvim_create_autocmd({"BufRead", "BufWrite"}, {
        pattern = "*",
        command = "set ts=4",
      })
    LUA
    # Should produce 2 entries (one per event).
    assert_equal 2, @editor.autocommands.size
  end
end
