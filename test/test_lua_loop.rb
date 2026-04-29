# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaLoop < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_new_timer_immediate_pump_fires
    @editor.lua.eval(<<~LUA)
      fired = 0
      local t = vim.loop.new_timer()
      t:start(0, 0, function() fired = fired + 1 end)
    LUA
    @editor.pump_lua_loop
    assert_equal 1, @editor.lua.eval('return fired').to_i
  end

  def test_timer_doesnt_fire_before_deadline
    @editor.lua.eval(<<~LUA)
      fired = 0
      local t = vim.loop.new_timer()
      t:start(60000, 0, function() fired = fired + 1 end)
    LUA
    @editor.pump_lua_loop
    assert_equal 0, @editor.lua.eval('return fired').to_i
  end

  def test_timer_repeat_stays_alive
    @editor.lua.eval(<<~LUA)
      fired = 0
      local t = vim.loop.new_timer()
      t:start(0, 0, function() fired = fired + 1 end)
    LUA
    @editor.pump_lua_loop
    @editor.pump_lua_loop
    # one-shot so only fires once
    assert_equal 1, @editor.lua.eval('return fired').to_i
  end

  def test_defer_fn_fires_on_pump
    @editor.lua.eval(<<~LUA)
      result = "before"
      vim.defer_fn(function() result = "after" end, 0)
    LUA
    @editor.pump_lua_loop
    assert_equal 'after', @editor.lua.eval('return result')
  end

  def test_schedule_fires_on_pump
    @editor.lua.eval(<<~LUA)
      ran = 0
      vim.schedule(function() ran = 1 end)
    LUA
    @editor.pump_lua_loop
    assert_equal 1, @editor.lua.eval('return ran').to_i
  end

  def test_uv_is_alias_for_loop
    assert_equal true, @editor.lua.eval('return vim.uv == vim.loop')
  end

  def test_loop_now_returns_milliseconds
    a = @editor.lua.eval('return vim.loop.now()').to_i
    sleep 0.01
    b = @editor.lua.eval('return vim.loop.now()').to_i
    assert_operator b, :>, a
  end

  def test_timer_stop_cancels_callback
    @editor.lua.eval(<<~LUA)
      fired = 0
      local t = vim.loop.new_timer()
      t:start(0, 0, function() fired = fired + 1 end)
      t:stop()
    LUA
    @editor.pump_lua_loop
    assert_equal 0, @editor.lua.eval('return fired').to_i
  end

  def test_timer_close_removes
    @editor.lua.eval(<<~LUA)
      local t = vim.loop.new_timer()
      t:start(60000, 0, function() end)
      t:close()
    LUA
    sched = @editor.instance_variable_get(:@lua_scheduler)
    assert sched.empty?
  end

  def test_pump_returns_count_fired
    @editor.lua.eval(<<~LUA)
      vim.defer_fn(function() end, 0)
      vim.defer_fn(function() end, 0)
    LUA
    n = @editor.pump_lua_loop
    assert_equal 2, n
  end
end
