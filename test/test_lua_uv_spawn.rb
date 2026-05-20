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
end
