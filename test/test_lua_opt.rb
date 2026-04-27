# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaOpt < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_opt_set_number
    @editor.lua.eval('vim.opt.tabstop = 4')
    assert_equal 4, @editor.settings.get(:tabstop)
  end

  def test_opt_set_bool
    @editor.lua.eval('vim.opt.number = true')
    assert_equal true, @editor.settings.get(:number)
  end

  def test_opt_set_string
    @editor.lua.eval('vim.opt.shell = "/bin/zsh"')
    assert_equal '/bin/zsh', @editor.settings.get(:shell)
  end

  def test_opt_get_via_proxy
    @editor.settings.set(:tabstop, 8)
    result = @editor.lua.eval('return vim.opt.tabstop:get()')
    assert_equal 8, result.to_i
  end

  def test_go_writes_global
    @editor.lua.eval('vim.go.shiftwidth = 6')
    assert_equal 6, @editor.settings.get(:shiftwidth)
  end

  def test_bo_writes_buffer_local
    buf = Rvim::Buffer.new(99)
    @editor.instance_variable_set(:@current_buffer, buf)
    @editor.lua.eval('vim.bo.tabstop = 12')
    assert_equal 12, buf.local_settings[:tabstop]
  end

  def test_wo_writes_global_for_now
    @editor.lua.eval('vim.wo.cursorline = true')
    assert_equal true, @editor.settings.get(:cursorline)
  end

  def test_round_trip_after_set
    @editor.lua.eval('vim.opt.tabstop = 16')
    result = @editor.lua.eval('return vim.opt.tabstop:get()')
    assert_equal 16, result.to_i
  end
end
