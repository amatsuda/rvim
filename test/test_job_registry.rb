# frozen_string_literal: true

require_relative 'test_helper'

# Rvim::JobRegistry: tracks live jobs, drains their queues each
# tick, dispatches on_stdout / on_stderr / on_exit callbacks on the
# main thread.

class TestJobRegistry < Test::Unit::TestCase
  class FakeJob
    attr_accessor :alive_flag, :queued, :exit_status, :killed_with
    attr_reader :id

    @@next = 100
    def initialize
      @id = (@@next += 1)
      @queued = []
      @alive_flag = true
      @reader_done = false
      @exit_status = nil
    end

    def start; end
    def drain; q = @queued.dup; @queued.clear; q; end
    def done?; @reader_done && @queued.empty?; end
    def alive?; @alive_flag; end
    def kill(sig); @killed_with = sig; @alive_flag = false; end
    def write(_text); true; end
    def close_stdin; end

    def finish!(status)
      @exit_status = status
      @alive_flag = false
      @reader_done = true
    end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @registry = Rvim::JobRegistry.new(@editor)
  end

  def test_register_starts_job_and_returns_id
    job = FakeJob.new
    id = @registry.register(job)
    assert_equal job.id, id
    assert_equal job, @registry.get(id)
  end

  def test_drain_all_groups_lines_per_stream_per_call
    job = FakeJob.new
    stdout_batches = []
    stderr_batches = []
    @registry.register(job,
                       on_stdout: ->(_id, data, name) { stdout_batches << [data, name] },
                       on_stderr: ->(_id, data, name) { stderr_batches << [data, name] })
    job.queued = [[:stdout, 'a'], [:stdout, 'b'], [:stderr, 'oops']]
    @registry.drain_all
    assert_equal [[%w[a b], 'stdout']], stdout_batches
    assert_equal [[['oops'], 'stderr']], stderr_batches
  end

  def test_drain_all_fires_on_exit_once_then_removes_entry
    job = FakeJob.new
    exit_calls = []
    @registry.register(job, on_exit: ->(_id, data, name) { exit_calls << [data, name] })
    @registry.drain_all
    assert_empty exit_calls, 'not done yet — no on_exit'

    job.finish!(7)
    @registry.drain_all
    assert_equal [[[7], 'exit']], exit_calls
    assert_equal 0, @registry.size, 'entry removed after exit fires'

    @registry.drain_all # second drain — must NOT fire again
    assert_equal [[[7], 'exit']], exit_calls
  end

  def test_write_forwards_string_and_array
    job = FakeJob.new
    seen = []
    job.define_singleton_method(:write) { |text| seen << text; true }
    id = @registry.register(job)
    @registry.write(id, 'plain')
    @registry.write(id, %w[a b c])
    assert_equal ['plain', "a\nb\nc\n"], seen
  end

  def test_stop_calls_kill
    job = FakeJob.new
    id = @registry.register(job)
    @registry.stop(id, 'HUP')
    assert_equal 'HUP', job.killed_with
  end

  def test_wait_returns_codes_aligned_with_ids_when_all_complete
    a = FakeJob.new; b = FakeJob.new
    @registry.register(a); @registry.register(b)
    a.finish!(0); b.finish!(1)
    assert_equal [0, 1], @registry.wait([a.id, b.id], 1000)
  end

  def test_wait_returns_minus_one_for_jobs_still_running_at_timeout
    j = FakeJob.new
    @registry.register(j)
    assert_equal [-1], @registry.wait([j.id], 50)
  end

  def test_wait_returns_minus_two_for_unknown_ids
    assert_equal [-2], @registry.wait([99_999], 50)
  end

  def test_shutdown_kills_every_live_job
    a = FakeJob.new; b = FakeJob.new
    @registry.register(a); @registry.register(b)
    @registry.shutdown
    assert_equal 'TERM', a.killed_with
    assert_equal 'TERM', b.killed_with
  end

  def test_callback_error_does_not_take_registry_down
    job = FakeJob.new
    @registry.register(job, on_stdout: ->(_id, _data, _name) { raise 'boom' })
    job.queued = [[:stdout, 'x']]
    assert_nothing_raised { @registry.drain_all }
    assert_match(/boom/, @editor.status_message.to_s)
  end
end
