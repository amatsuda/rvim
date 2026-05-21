# frozen_string_literal: true

require_relative 'test_helper'

# libuv-style spawn API (vim.uv.spawn + vim.uv.new_pipe). Backs
# telescope/plenary's async finder model — process spawn with
# separate stdin/stdout/stderr pipes and a read_start callback per
# pipe.

class TestLuaUvSpawn < Test::Unit::TestCase
  def setup
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def pump_until(timeout_s = 2.0, &predicate)
    deadline = Time.now + timeout_s
    until predicate.call
      break if Time.now > deadline

      @editor.pump_lua_loop
      sleep 0.02
    end
  end

  def test_spawn_echo_pipes_stdout_through_read_start
    @editor.lua.eval(<<~LUA)
      collected = ""
      done = false
      local stdout = vim.uv.new_pipe(false)
      local handle, pid = vim.uv.spawn("echo",
        { args = {"hello", "world"}, stdio = {nil, stdout, nil} },
        function(code, _) done = true; exit_code = code end)
      stdout:read_start(function(err, data)
        if data then collected = collected .. data end
      end)
    LUA
    pump_until { @editor.lua.eval('return done') }
    assert_match(/hello world/, @editor.lua.eval('return collected').to_s)
    assert_equal 0, @editor.lua.eval('return exit_code').to_i
  end

  def test_pipe_buffers_data_across_read_stop_read_start_cycle
    # Regression: telescope's LinesPipe reads one chunk, calls
    # read_stop, then read_start again. Our pipe must buffer data
    # received between stop and the next start instead of dropping it.
    @editor.lua.eval(<<~LUA)
      collected = ""
      done = false
      local stdout = vim.uv.new_pipe(false)
      local handle = vim.uv.spawn("printf",
        { args = {"line1\\nline2\\nline3\\n"}, stdio = {nil, stdout, nil} },
        function() done = true end)
      stdout:read_start(function(_, data)
        if data then
          collected = collected .. data
          stdout:read_stop()
          -- Re-start to fetch the next chunk. If our buffer drops
          -- data while stopped, we'll only see line1 and miss the rest.
          vim.schedule(function()
            stdout:read_start(function(_, d2)
              if d2 then collected = collected .. d2 end
            end)
          end)
        end
      end)
    LUA
    pump_until { @editor.lua.eval('return collected').to_s.include?('line3') }
    body = @editor.lua.eval('return collected').to_s
    assert_match(/line1/, body)
    assert_match(/line2/, body)
    assert_match(/line3/, body)
  end

  def test_spawn_exit_callback_receives_code
    @editor.lua.eval(<<~LUA)
      done = false
      vim.uv.spawn("false", { stdio = {nil, nil, nil} }, function(code, _)
        done = true; exit_code = code
      end)
    LUA
    pump_until { @editor.lua.eval('return done') }
    assert_equal 1, @editor.lua.eval('return exit_code').to_i
  end

  def test_stdin_pipe_write_reaches_process
    @editor.lua.eval(<<~LUA)
      collected = ""
      done = false
      local stdin = vim.uv.new_pipe(false)
      local stdout = vim.uv.new_pipe(false)
      local handle = vim.uv.spawn("cat",
        { stdio = {stdin, stdout, nil} },
        function() done = true end)
      stdout:read_start(function(_, d) if d then collected = collected .. d end end)
      stdin:write("through stdin")
      stdin:close()
    LUA
    pump_until { @editor.lua.eval('return done') }
    assert_match(/through stdin/, @editor.lua.eval('return collected').to_s)
  end

  def test_coroutine_pipe_callback_can_resume_yielded_thread
    # Regression: rufus-lua pins Rufus::Lua::Function#@pointer to the
    # lua_State* that was active at construction. When state.function
    # dispatches a Ruby callback from inside a coroutine T1, any
    # Function arg (e.g. the cb passed to read_start) captures T1's
    # pointer. Firing it later from the drainer would run Lua code on
    # T1's state — coroutine.running() returns T1 — and the call to
    # coroutine.resume(T1) inside the cb body fails with "cannot
    # resume running coroutine". The fix: Rvim::Lua::Runtime patches
    # Function#call to swap @pointer to the main state for the call.
    #
    # This test exercises that path with a coroutine-driven mini-finder
    # that mirrors telescope's LinesPipe pattern: spawn a process,
    # read its output through a yielded receiver, accumulate lines.
    @editor.lua.eval(<<~LUA)
      collected = {}
      done = false
      error_msg = nil

      local function oneshot()
        local sent, value, cb = false, nil, nil
        return function(v)
          if cb then cb(v) else sent, value = true, v end
        end,
        function()
          if sent then return value end
          return coroutine.yield(function(c) cb = c end)
        end
      end

      local thread = coroutine.create(function()
        local stdout = vim.uv.new_pipe(false)
        local exit_tx, exit_rx = oneshot()
        vim.uv.spawn("printf",
          { args = {"a\\nb\\nc\\n"}, stdio = {nil, stdout, nil} },
          function() exit_tx(true) end)

        local function read()
          local tx, rx = oneshot()
          stdout:read_start(function(_, data)
            stdout:read_stop()
            tx(data)
          end)
          return rx()
        end

        local function step(thr, ...)
          local ok, fn = coroutine.resume(thr, ...)
          if not ok then error_msg = fn return end
          if coroutine.status(thr) ~= "dead" and type(fn) == "function" then
            fn(function(v) step(thr, v) end)
          end
        end

        while true do
          local data = read()
          if data == nil then break end
          for line in data:gmatch("[^\\n]+") do
            table.insert(collected, line)
          end
        end
        done = true
      end)

      local function step(thr, ...)
        local ok, fn = coroutine.resume(thr, ...)
        if not ok then error_msg = fn return end
        if coroutine.status(thr) ~= "dead" and type(fn) == "function" then
          fn(function(v) step(thr, v) end)
        end
      end

      step(thread)
    LUA
    pump_until { @editor.lua.eval('return done') }
    assert_nil @editor.lua.eval('return error_msg'),
               'coroutine resume should not fail with "cannot resume running coroutine"'
    collected = @editor.lua.eval('return table.concat(collected, ",")').to_s
    assert_equal 'a,b,c', collected
  end
end
