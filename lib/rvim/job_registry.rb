# frozen_string_literal: true

module Rvim
  # Holds live Rvim::Job instances by id, drains their queues on
  # each render-loop tick, and dispatches per-stream Lua-style
  # callbacks ({ on_stdout:, on_stderr:, on_exit: }) on the MAIN
  # THREAD (where buffer mutations are safe).
  #
  # Owned by Rvim::Editor; pumped from Editor#pump_jobs.
  class JobRegistry
    def initialize(editor)
      @editor = editor
      @jobs = {} # id -> { job:, on_stdout:, on_stderr:, on_exit:, sent_exit: false }
    end

    # Register a not-yet-started Job with optional callbacks. Each
    # callback is a Ruby callable matching NeoVim's jobstart shape:
    # `fn.(id, data, stream_name)` where data is an Array<String>
    # of new lines and stream_name is "stdout" / "stderr" / "exit"
    # ("exit" sends the exit code as `data` for symmetry).
    def register(job, on_stdout: nil, on_stderr: nil, on_exit: nil)
      job.start
      @jobs[job.id] = {
        job: job,
        on_stdout: on_stdout,
        on_stderr: on_stderr,
        on_exit: on_exit,
        sent_exit: false,
      }
      job.id
    end

    def get(id)
      entry = @jobs[id]
      entry && entry[:job]
    end

    # Send `data` (String or Array<String>) to the job's stdin.
    def write(id, data)
      job = get(id)
      return false unless job

      text = data.is_a?(Array) ? "#{data.join("\n")}\n" : data.to_s
      job.write(text)
    end

    def stop(id, signal = 'TERM')
      job = get(id)
      return false unless job

      job.kill(signal)
      true
    end

    # Drain every job's queue, group by stream, fire callbacks.
    # Removes entries whose job is done? AND whose on_exit fired.
    def drain_all
      @jobs.each_value do |entry|
        drain_entry(entry)
      end
      @jobs.reject! { |_, e| e[:job].done? && e[:sent_exit] }
    end

    # Block (up to timeout_ms; nil means forever) until every id has
    # exited or the deadline elapses. While blocked, ticks the same
    # pumps the render loop would tick so callbacks keep firing.
    # Returns Array<Integer> aligned with `ids` — exit code or -1.
    def wait(ids, timeout_ms = nil)
      deadline = timeout_ms ? monotonic + timeout_ms / 1000.0 : nil
      loop do
        all_done = ids.all? { |id| (j = get(id)).nil? || j.done? }
        break if all_done
        break if deadline && monotonic >= deadline

        pump_event_loop
        sleep 0.01
      end
      ids.map do |id|
        j = get(id)
        if j.nil?
          -2 # never registered / already reaped
        elsif j.done?
          j.exit_status || 0
        else
          -1 # timed out, still running
        end
      end
    end

    # Send SIGTERM to every live job. Called from Editor#finalize so
    # quitting the editor doesn't leak processes.
    def shutdown
      @jobs.each_value do |entry|
        entry[:job].kill('TERM') if entry[:job].alive?
      end
    end

    def size
      @jobs.size
    end

    def empty?
      @jobs.empty?
    end

    private def drain_entry(entry)
      job = entry[:job]
      stdout_lines = []
      stderr_lines = []
      job.drain.each do |stream, payload|
        case stream
        when :stdout then stdout_lines << payload
        when :stderr then stderr_lines << payload
        end
      end
      invoke(entry[:on_stdout], job.id, stdout_lines, 'stdout') unless stdout_lines.empty?
      invoke(entry[:on_stderr], job.id, stderr_lines, 'stderr') unless stderr_lines.empty?
      return unless job.done? && !entry[:sent_exit]

      entry[:sent_exit] = true
      invoke(entry[:on_exit], job.id, [job.exit_status.to_i], 'exit')
    end

    # Callbacks are user-controlled — never let an exception in one
    # take the registry (and the editor) down. Log to the editor's
    # status message on failure.
    private def invoke(cb, *args)
      return if cb.nil?

      cb.call(*args)
    rescue StandardError => e
      @editor.status_message = "job callback error: #{e.message}" if @editor.respond_to?(:status_message=)
    end

    private def pump_event_loop
      @editor.pump_jobs if @editor.respond_to?(:pump_jobs)
      @editor.pump_lua_loop if @editor.respond_to?(:pump_lua_loop)
      @editor.pump_async_commands if @editor.respond_to?(:pump_async_commands)
      @editor.lsp.pump if @editor.respond_to?(:lsp) && @editor.lsp.respond_to?(:pump)
    rescue StandardError
      # Same swallow-and-keep-going as invoke; pumps should never
      # raise but defend against misbehaving callbacks.
    end

    private def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
