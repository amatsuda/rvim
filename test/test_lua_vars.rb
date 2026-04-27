# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaVars < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_g_set_writes_to_let_vars
    @editor.lua.eval('vim.g.mapleader = " "')
    assert_equal ' ', @editor.let_vars['mapleader']
  end

  def test_g_get_reads_from_let_vars
    @editor.let_vars['hello'] = 'world'
    assert_equal 'world', @editor.lua.eval('return vim.g.hello')
  end

  def test_g_unset_returns_nil
    assert_nil @editor.lua.eval('return vim.g.never_set')
  end

  def test_b_set_writes_to_current_buffer_vars
    buf = Rvim::Buffer.new(50)
    @editor.instance_variable_set(:@current_buffer, buf)
    @editor.lua.eval('vim.b.tag = "ruby"')
    assert_equal 'ruby', buf.vars['tag']
  end

  def test_b_get_reads_from_current_buffer_vars
    buf = Rvim::Buffer.new(51)
    buf.vars['ft'] = 'lua'
    @editor.instance_variable_set(:@current_buffer, buf)
    assert_equal 'lua', @editor.lua.eval('return vim.b.ft')
  end

  def test_w_set_writes_to_current_window_vars
    buf = Rvim::Buffer.new(52)
    win = Rvim::Window.new(buf)
    @editor.instance_variable_set(:@current_window, win)
    @editor.lua.eval('vim.w.zoom = 1')
    assert_equal 1, win.vars['zoom'].to_i
  end

  def test_t_set_writes_to_current_tab_vars
    buf = Rvim::Buffer.new(53)
    win = Rvim::Window.new(buf)
    tab = Rvim::Tab.new(win)
    @editor.instance_variable_set(:@tabs, [tab])
    @editor.instance_variable_set(:@current_tab_index, 0)
    @editor.lua.eval('vim.t.layout = "vertical"')
    assert_equal 'vertical', tab.vars['layout']
  end

  def test_g_round_trip
    @editor.lua.eval('vim.g.foo = "bar"; vim.g.baz = vim.g.foo')
    assert_equal 'bar', @editor.let_vars['baz']
  end
end
