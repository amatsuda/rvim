# frozen_string_literal: true

require_relative 'test_helper'

# Rvim::Job: popen3-based subprocess with separate stdout/stderr,
# stdin pipe, kill (TERM/KILL escalation), drain queue. These tests
# spawn real subprocesses so they take a few seconds combined.

class TestJob < Test::Unit::TestCase
  def make_job(cmd)
    Rvim::Job.new(cmd, shell: '/bin/sh', shellcmdflag: '-c')
  end

  def wait_until(timeout: 2.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.02
    end
  end

  def drain_until_done(job)
    out = []
    while wait_until { job.done? || !job.drain.then { |d| out.concat(d); false } }
      break if job.done?
    end
    out.concat(job.drain) while !job.drain.empty?
    out
  end

  def test_stdout_and_stderr_arrive_on_separate_streams
    job = make_job("printf 'out\\n' ; printf 'err\\n' >&2")
    job.start
    wait_until { job.done? }
    drained = job.drain
    by_stream = drained.group_by(&:first).transform_values { |v| v.map(&:last) }
    assert_equal ['out'], by_stream[:stdout]
    assert_equal ['err'], by_stream[:stderr]
  end

  def test_exit_status_captures_zero
    job = make_job('true')
    job.start
    wait_until { job.done? }
    assert_equal 0, job.exit_status
  end

  def test_exit_status_captures_nonzero
    job = make_job('exit 17')
    job.start
    wait_until { job.done? }
    assert_equal 17, job.exit_status
  end

  def test_stdin_can_be_written_and_closed
    # `cat` echoes stdin to stdout — verifies the stdin pipe works.
    job = make_job('cat')
    job.start
    job.write("hello\nworld\n")
    job.close_stdin
    wait_until { job.done? }
    out = job.drain.select { |s, _| s == :stdout }.map(&:last)
    assert_equal %w[hello world], out
  end

  def test_kill_terminates_a_long_running_process
    job = make_job('sleep 5')
    job.start
    refute job.done?
    job.kill('TERM')
    assert wait_until(timeout: 1.0) { job.done? }, 'kill should fast-track exit'
  end

  def test_drain_is_non_blocking
    job = make_job("sleep 0.05 ; echo done")
    job.start
    # Immediately drain — should return empty, not block.
    assert_equal [], job.drain
    wait_until { job.done? }
    assert_equal [[:stdout, 'done']], job.drain
  end

  def test_assigned_id_is_monotonic
    a = make_job('true')
    b = make_job('true')
    assert_operator b.id, :>, a.id
  end

  def test_array_cmd_runs_argv_directly
    # Pass an argv array — no shell interpretation, so $HOME stays
    # literal.
    job = Rvim::Job.new(%w[echo $HOME], shell: '/bin/sh', shellcmdflag: '-c')
    job.start
    wait_until { job.done? }
    out = job.drain.select { |s, _| s == :stdout }.map(&:last)
    assert_equal ['$HOME'], out, 'no shell expansion when cmd is argv'
  end

  def test_env_is_passed_to_subprocess
    job = Rvim::Job.new('echo "$RVIM_TEST_VAR"',
                        shell: '/bin/sh', shellcmdflag: '-c',
                        env: { 'RVIM_TEST_VAR' => 'hello' })
    job.start
    wait_until { job.done? }
    out = job.drain.select { |s, _| s == :stdout }.map(&:last)
    assert_equal ['hello'], out
  end

  def test_cwd_changes_working_directory
    job = Rvim::Job.new('pwd', shell: '/bin/sh', shellcmdflag: '-c', cwd: '/tmp')
    job.start
    wait_until { job.done? }
    out = job.drain.select { |s, _| s == :stdout }.map(&:last)
    # /tmp may symlink to /private/tmp on macOS — accept either.
    assert(out.first == '/tmp' || out.first == '/private/tmp',
           "expected pwd inside /tmp, got #{out.first.inspect}")
  end
end
