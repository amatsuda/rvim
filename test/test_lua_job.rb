# frozen_string_literal: true

require_relative 'test_helper'

# Lua-level integration: vim.fn.jobstart / jobsend / jobstop /
# jobwait, vim.system, vim.wait. Spawns real subprocesses; combined
# this file takes a few seconds.

class TestLuaJob < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def wait_for_done(ids, timeout: 3.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      all_done = ids.all? do |id|
        j = @editor.jobs.get(id)
        j.nil? || j.done?
      end
      break true if all_done
      break false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      @editor.pump_jobs
      sleep 0.02
    end
  end

  def test_jobstart_returns_an_integer_id
    id = @editor.lua.eval(<<~LUA).to_i
      return vim.fn.jobstart({'true'}, {})
    LUA
    assert_operator id, :>, 0
    wait_for_done([id])
  end

  def test_on_stdout_receives_emitted_lines
    @editor.lua.eval(<<~LUA)
      stdout_lines = {}
      job_id = vim.fn.jobstart({'sh', '-c', "printf 'a\\nb\\n'"}, {
        on_stdout = function(_id, data, _name)
          for _, l in ipairs(data) do table.insert(stdout_lines, l) end
        end,
      })
    LUA
    id = @editor.lua.eval('return job_id').to_i
    wait_for_done([id])
    @editor.pump_jobs # drain the final batch
    @editor.lua.eval(<<~LUA)
      joined = table.concat(stdout_lines, ',')
    LUA
    assert_equal 'a,b', @editor.lua.eval('return joined')
  end

  def test_on_stderr_receives_emitted_lines
    @editor.lua.eval(<<~LUA)
      stderr_lines = {}
      job_id = vim.fn.jobstart({'sh', '-c', "echo oops >&2"}, {
        on_stderr = function(_id, data, _name)
          for _, l in ipairs(data) do table.insert(stderr_lines, l) end
        end,
      })
    LUA
    id = @editor.lua.eval('return job_id').to_i
    wait_for_done([id])
    @editor.pump_jobs
    @editor.lua.eval('joined = table.concat(stderr_lines, ",")')
    assert_equal 'oops', @editor.lua.eval('return joined')
  end

  def test_on_exit_fires_with_exit_code
    @editor.lua.eval(<<~LUA)
      exit_code = nil
      job_id = vim.fn.jobstart({'sh', '-c', 'exit 5'}, {
        on_exit = function(_id, data, _name)
          exit_code = data[1]
        end,
      })
    LUA
    id = @editor.lua.eval('return job_id').to_i
    wait_for_done([id])
    @editor.pump_jobs
    assert_equal 5, @editor.lua.eval('return exit_code').to_i
  end

  def test_jobsend_writes_to_stdin
    # `head -n1` reads one line then exits — avoids needing a
    # stdin-close API to make the child terminate.
    @editor.lua.eval(<<~LUA)
      received = {}
      job_id = vim.fn.jobstart({'head', '-n', '1'}, {
        on_stdout = function(_id, data, _name)
          for _, l in ipairs(data) do table.insert(received, l) end
        end,
      })
      vim.fn.jobsend(job_id, 'hello\\n')
    LUA
    id = @editor.lua.eval('return job_id').to_i
    wait_for_done([id])
    @editor.pump_jobs
    @editor.lua.eval('joined = table.concat(received, ",")')
    assert_equal 'hello', @editor.lua.eval('return joined')
  end

  def test_jobstop_terminates_a_long_running_job
    id = @editor.lua.eval(<<~LUA).to_i
      return vim.fn.jobstart({'sleep', '5'}, {})
    LUA
    refute @editor.jobs.get(id).done?
    @editor.lua.eval("vim.fn.jobstop(#{id})")
    assert wait_for_done([id], timeout: 1.0), 'jobstop didn\'t terminate fast enough'
  end

  def test_jobwait_returns_exit_codes_aligned_with_ids
    @editor.lua.eval(<<~LUA)
      a = vim.fn.jobstart({'sh', '-c', 'exit 0'}, {})
      b = vim.fn.jobstart({'sh', '-c', 'exit 3'}, {})
      codes = vim.fn.jobwait({a, b}, 2000)
    LUA
    a = @editor.lua.eval('return codes[1]').to_i
    b = @editor.lua.eval('return codes[2]').to_i
    assert_equal 0, a
    assert_equal 3, b
  end

  def test_jobwait_timeout_returns_negative_one
    @editor.lua.eval(<<~LUA)
      id = vim.fn.jobstart({'sleep', '5'}, {})
      codes = vim.fn.jobwait({id}, 100)
      vim.fn.jobstop(id)
    LUA
    code = @editor.lua.eval('return codes[1]').to_i
    assert_equal(-1, code)
    wait_for_done([@editor.lua.eval('return id').to_i])
  end

  def test_vim_system_callback_receives_stdout_stderr_and_code
    @editor.lua.eval(<<~LUA)
      result = nil
      vim.system({'sh', '-c', "echo out; echo err >&2; exit 2"}, {}, function(_id, data, _name)
        result = data[1]
      end)
    LUA
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3.0
    until @editor.lua.eval('return result ~= nil') == true
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      @editor.pump_jobs
      sleep 0.02
    end
    assert_equal 2,    @editor.lua.eval('return result.code').to_i
    assert_match(/out/, @editor.lua.eval('return result.stdout'))
    assert_match(/err/, @editor.lua.eval('return result.stderr'))
  end

  def test_vim_wait_returns_true_when_predicate_satisfies
    # Predicate flips to true after 100ms thanks to a deferred timer.
    @editor.lua.eval(<<~LUA)
      flag = false
      vim.defer_fn(function() flag = true end, 0)
      ok = vim.wait(2000, function() return flag end, 20)
    LUA
    assert_equal true, @editor.lua.eval('return ok')
  end

  def test_vim_wait_returns_false_on_timeout
    @editor.lua.eval(<<~LUA)
      ok = vim.wait(50, function() return false end, 20)
    LUA
    assert_equal false, @editor.lua.eval('return ok')
  end
end
