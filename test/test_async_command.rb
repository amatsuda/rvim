# frozen_string_literal: true

require_relative 'test_helper'

# AsyncCommand spawns a subprocess and streams its stdout/stderr into
# a thread-safe queue. The editor render loop polls #drain instead of
# blocking on the pipe so long-running test runs don't freeze the UI.

class TestAsyncCommand < Test::Unit::TestCase
  def make_job(cmd)
    Rvim::AsyncCommand.new(cmd, shell: '/bin/sh', shellcmdflag: '-c')
  end

  def wait_until(timeout: 2.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.02
    end
  end

  def test_captures_stdout_lines
    job = make_job("printf 'a\\nb\\nc\\n'")
    job.start
    wait_until { job.done? }
    lines = job.drain
    assert_equal %w[a b c], lines
  end

  def test_captures_stderr_combined_with_stdout
    job = make_job("printf 'out\\n'; printf 'err\\n' >&2")
    job.start
    wait_until { job.done? }
    lines = job.drain
    assert_equal %w[out err].sort, lines.sort
  end

  def test_exit_status_zero_on_success
    job = make_job('true')
    job.start
    wait_until { job.done? }
    assert_equal 0, job.exit_status
  end

  def test_exit_status_nonzero_on_failure
    job = make_job('exit 7')
    job.start
    wait_until { job.done? }
    assert_equal 7, job.exit_status
  end

  def test_drain_is_non_blocking
    # Spawn a slow command so output isn't immediately ready.
    job = make_job("sleep 0.05; printf 'hi\\n'")
    job.start
    # Drain right away — should return [] without blocking.
    assert_equal [], job.drain
    wait_until { job.done? }
    assert_equal ['hi'], job.drain
  end

  def test_done_is_false_while_running
    job = make_job('sleep 0.05')
    job.start
    refute job.done?, 'not done yet'
    wait_until { job.done? }
    assert job.done?
  end
end

class TestEditorPumpAsyncCommands < Test::Unit::TestCase
  class FakeJob
    attr_accessor :queued_lines, :status

    def initialize
      @queued_lines = []
      @done = false
      @status = nil
    end

    def drain
      lines = @queued_lines.dup
      @queued_lines.clear
      lines
    end

    def done?; @done; end
    def finish!(status); @done = true; @status = status; end
    def exit_status; @status; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @buf = Rvim::Buffer.new(99, 'term://echo', encoding: 'UTF-8')
    @buf.lines = ['Running: echo', '']
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@buffers, { 99 => @buf })
    @editor.instance_variable_set(:@buffer_order, [99])
  end

  def test_appends_drained_lines_to_target_buffer
    job = FakeJob.new
    job.queued_lines.push('line one', 'line two')
    @editor.instance_variable_set(:@async_commands,
      [{ job: job, buffer: @buf, label: 'echo' }])
    @editor.pump_async_commands
    assert_equal ['Running: echo', '', 'line one', 'line two'], @buf.lines
  end

  def test_no_op_when_queue_empty_and_running
    job = FakeJob.new
    @editor.instance_variable_set(:@async_commands,
      [{ job: job, buffer: @buf, label: 'echo' }])
    @editor.pump_async_commands
    assert_equal ['Running: echo', ''], @buf.lines
    assert_equal 1, @editor.instance_variable_get(:@async_commands).size
  end

  def test_finalizes_completed_job_with_exit_footer
    job = FakeJob.new
    job.queued_lines.push('done output')
    job.finish!(0)
    @editor.instance_variable_set(:@async_commands,
      [{ job: job, buffer: @buf, label: 'echo' }])
    @editor.pump_async_commands
    assert_equal ['Running: echo', '', 'done output', '[Exit 0]'], @buf.lines
    assert_empty @editor.instance_variable_get(:@async_commands), 'job removed'
    assert_match(/echo →/, @editor.status_message.to_s)
  end

  def test_keeps_buffer_of_lines_in_sync_for_current_buffer
    job = FakeJob.new
    job.queued_lines.push('streamed')
    @editor.instance_variable_set(:@async_commands,
      [{ job: job, buffer: @buf, label: 'echo' }])
    @editor.pump_async_commands
    # Editor re-binds @buffer_of_lines to the buffer's lines so the
    # renderer sees the appended content immediately.
    assert_equal @buf.lines, @editor.buffer_of_lines
  end

  # ----- tail-mode follow -----

  def test_tail_mode_advances_cursor_to_new_bottom_when_at_bottom
    @editor.instance_variable_set(:@line_index, @buf.lines.size - 1)
    job = FakeJob.new
    job.queued_lines.push('a', 'b', 'c')
    @editor.instance_variable_set(:@async_commands,
      [{ job: job, buffer: @buf, label: 'echo' }])
    @editor.pump_async_commands
    assert_equal @buf.lines.size - 1, @editor.line_index, 'cursor follows new bottom'
  end

  def test_tail_mode_does_not_move_cursor_when_scrolled_up
    # User is reading line 0 (header).
    @editor.instance_variable_set(:@line_index, 0)
    job = FakeJob.new
    job.queued_lines.push('a', 'b', 'c')
    @editor.instance_variable_set(:@async_commands,
      [{ job: job, buffer: @buf, label: 'echo' }])
    @editor.pump_async_commands
    assert_equal 0, @editor.line_index, 'cursor stays put'
  end

  def test_tail_mode_re_engages_after_user_jumps_to_bottom
    @editor.instance_variable_set(:@line_index, 0)
    job = FakeJob.new
    job.queued_lines.push('a', 'b')
    @editor.instance_variable_set(:@async_commands,
      [{ job: job, buffer: @buf, label: 'echo' }])
    @editor.pump_async_commands
    assert_equal 0, @editor.line_index

    # User presses G; cursor is now at last line.
    @editor.instance_variable_set(:@line_index, @buf.lines.size - 1)
    job.queued_lines.push('c', 'd')
    @editor.pump_async_commands
    assert_equal @buf.lines.size - 1, @editor.line_index
  end

  def test_tail_mode_follows_in_non_current_buffer_via_buffer_line_index
    other = Rvim::Buffer.new(2, 'other')
    other.lines = ['hello']
    @editor.instance_variable_set(:@current_buffer, other)
    @editor.instance_variable_set(:@buffer_of_lines, other.lines)

    @buf.line_index = @buf.lines.size - 1
    job = FakeJob.new
    job.queued_lines.push('streamed')
    @editor.instance_variable_set(:@async_commands,
      [{ job: job, buffer: @buf, label: 'echo' }])
    @editor.pump_async_commands
    assert_equal @buf.lines.size - 1, @buf.line_index
    assert_equal 'streamed', @buf.lines.last
  end
end
