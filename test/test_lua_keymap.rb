# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaKeymap < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_keymap_set_normal_mode
    @editor.lua.eval('vim.keymap.set("n", "Y", "y$")')
    found = nil
    @editor.keymap.each(:normal) { |lhs, m| found = m if lhs == 'Y' }
    refute_nil found
    assert_equal 'y$', found.rhs
  end

  def test_keymap_set_with_silent
    @editor.lua.eval('vim.keymap.set("n", "<leader>w", ":write<CR>", { silent = true })')
    found = nil
    @editor.keymap.each(:normal) { |_, m| found = m if m.rhs == ":write\r" }
    refute_nil found
    assert_equal true, found.silent
  end

  def test_keymap_set_noremap
    @editor.lua.eval('vim.keymap.set("n", "Q", "q", { noremap = true })')
    found = nil
    @editor.keymap.each(:normal) { |lhs, m| found = m if lhs == 'Q' }
    refute_nil found
    assert_equal false, found.recursive
  end

  def test_keymap_set_defaults_to_non_recursive
    # NeoVim's vim.keymap.set is non-recursive by default (noremap=true
    # is the default behavior). Without this, `map.set('v', '>', '>gv')`
    # would recurse infinitely on the inner '>'.
    @editor.lua.eval('vim.keymap.set("v", ">", ">gv")')
    found = nil
    @editor.keymap.each(:visual) { |lhs, m| found = m if lhs == '>' }
    refute_nil found
    assert_equal false, found.recursive
  end

  def test_keymap_set_remap_true_opts_into_recursive
    @editor.lua.eval('vim.keymap.set("n", "Q", "q", { remap = true })')
    found = nil
    @editor.keymap.each(:normal) { |lhs, m| found = m if lhs == 'Q' }
    refute_nil found
    assert_equal true, found.recursive
  end

  def test_keymap_set_multiple_modes
    @editor.lua.eval('vim.keymap.set({"n", "v"}, "X", "x")')
    n = nil
    v = nil
    @editor.keymap.each(:normal) { |lhs, m| n = m if lhs == 'X' }
    @editor.keymap.each(:visual) { |lhs, m| v = m if lhs == 'X' }
    refute_nil n
    refute_nil v
  end

  def test_keymap_set_callback_rhs
    @editor.lua.eval(<<~LUA)
      vim.g.fired = 0
      vim.keymap.set("n", "<leader>x", function() vim.g.fired = 1 end)
    LUA
    cb = nil
    @editor.keymap.each(:normal) { |lhs, m| cb = m.callback if lhs == "\\x" }
    refute_nil cb
    cb.call
    assert_equal 1, @editor.let_vars['fired'].to_i
  end

  def test_keymap_del_removes
    @editor.lua.eval('vim.keymap.set("n", "Y", "y$")')
    @editor.lua.eval('vim.keymap.del("n", "Y")')
    found = nil
    @editor.keymap.each(:normal) { |lhs, _| found = lhs if lhs == 'Y' }
    assert_nil found
  end

  def test_keymap_set_insert_mode
    @editor.lua.eval('vim.keymap.set("i", "jk", "<Esc>")')
    found = nil
    @editor.keymap.each(:insert) { |lhs, m| found = m if lhs == 'jk' }
    refute_nil found
  end

  def test_keymap_lhs_expansion
    @editor.lua.eval('vim.keymap.set("n", "<CR>", "G")')
    found = nil
    @editor.keymap.each(:normal) { |lhs, m| found = m if lhs == "\r" }
    refute_nil found
  end
end
