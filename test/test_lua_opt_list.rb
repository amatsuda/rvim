# frozen_string_literal: true

require_relative 'test_helper'

# vim.opt.<csv_option>:append/prepend/remove — used heavily by NeoVim
# configs (e.g. `vim.opt.clipboard:append('unnamedplus')`,
# `vim.opt.rtp:prepend('~/.vim')`). Without this, the assignment
# silently does nothing and downstream behavior (clipboard sync,
# require resolution) is broken.
class TestLuaOptList < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_append_to_empty_csv
    @editor.lua.eval("vim.opt.clipboard:append('unnamedplus')")
    assert_equal 'unnamedplus', @editor.settings.get(:clipboard)
  end

  def test_append_extends_existing_csv
    @editor.settings.set(:clipboard, 'unnamed')
    @editor.lua.eval("vim.opt.clipboard:append('unnamedplus')")
    assert_equal 'unnamed,unnamedplus', @editor.settings.get(:clipboard)
  end

  def test_append_dedupes
    @editor.settings.set(:clipboard, 'unnamedplus')
    @editor.lua.eval("vim.opt.clipboard:append('unnamedplus')")
    assert_equal 'unnamedplus', @editor.settings.get(:clipboard)
  end

  def test_prepend_puts_at_front
    @editor.settings.set(:clipboard, 'unnamed')
    @editor.lua.eval("vim.opt.clipboard:prepend('unnamedplus')")
    assert_equal 'unnamedplus,unnamed', @editor.settings.get(:clipboard)
  end

  def test_remove_drops_value
    @editor.settings.set(:clipboard, 'unnamed,unnamedplus')
    @editor.lua.eval("vim.opt.clipboard:remove('unnamedplus')")
    assert_equal 'unnamed', @editor.settings.get(:clipboard)
  end

  def test_append_to_runtimepath
    base = @editor.settings.get(:runtimepath).to_s
    @editor.lua.eval("vim.opt.runtimepath:append('/tmp/extra')")
    assert_includes @editor.settings.get(:runtimepath).split(','), '/tmp/extra'
    assert @editor.settings.get(:runtimepath).start_with?(base.split(',').first)
  end

  def test_get_still_works_after_methods_added
    @editor.settings.set(:tabstop, 4)
    val = @editor.lua.eval('return vim.opt.tabstop:get()')
    assert_equal 4, val.to_i
  end

  def test_assignment_still_works
    @editor.lua.eval('vim.opt.tabstop = 6')
    assert_equal 6, @editor.settings.get(:tabstop)
  end
end
