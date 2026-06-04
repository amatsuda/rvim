# frozen_string_literal: true

require 'open3'

module Rvim
  # A subprocess with separate stdout/stderr streams and a writable
  # stdin. Reader threads drain each pipe line-by-line into a
  # thread-safe queue so the main thread can drain on its own clock.
  #
  # This is the richer cousin of Rvim::AsyncCommand: stdin pipe,
  # signal-based kill (TERM with KILL escalation), per-stream lines.
  # Used by:
  #   - The Lua jobstart family (lib/rvim/lua/job.rb)
  #   - Rvim::AsyncCommand (now a facade over this class)
  class Job
    attr_reader :exit_status, :id

    @@next_id = 0
    @@id_mutex = Mutex.new

    def self.allocate_id
      @@id_mutex.synchronize { @@next_id += 1 }
    end

    def initialize(cmd, shell: nil, shellcmdflag: nil, env: nil, cwd: nil, no_stdin: false)
      @cmd = cmd
      @shell = shell
      @shellcmdflag = shellcmdflag
      @env = env
      @cwd = cwd
      # When true, redirect stdin to /dev/null at spawn time. Tools
      # like `rg pattern` (no path) read stdin if it's a pipe but
      # search cwd if stdin points at /dev/null — popen3's default
      # pipe stdin makes rg sit on empty input forever.
      @no_stdin = no_stdin
      @queue = Thread::Queue.new
      @stdout_open = false
      @stderr_open = false
      @reader_done = false
      @exit_status = nil
      @id = self.class.allocate_id
      @killed = false
    end

    # Spawn the subprocess. `cmd` is either a string (run via shell)
    # or an array (exec directly). Mixing depends on what the caller
    # passed in — strings get joined under @shell, arrays pass straight
    # to popen3.
    def start
      argv = build_argv
      spawn_opts = {}
      spawn_opts[:chdir] = @cwd if @cwd
      @env ||= {}
      if @no_stdin
        # Hand-roll the pipes so we can redirect stdin to /dev/null.
        # popen3 always creates a stdin pipe, and closing our end of
        # the pipe still leaves the child looking at a pipe (just
        # empty), which is different from looking at /dev/null —
        # rg's behaviour, for instance, branches on the latter.
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        pid = Process.spawn(@env, *argv, spawn_opts.merge(in: '/dev/null', out: out_w, err: err_w))
        out_w.close
        err_w.close
        @stdin = nil
        @wait_thread = Process.detach(pid)
        # detach returns a Thread whose #pid + #value match popen3.
        @stdout_open = true
        @stderr_open = true
        @stdout_reader = spawn_reader(out_r, :stdout) { @stdout_open = false }
        @stderr_reader = spawn_reader(err_r, :stderr) { @stderr_open = false }
      else
        @stdin, stdout, stderr, @wait_thread = Open3.popen3(@env, *argv, spawn_opts)
        @stdout_open = true
        @stderr_open = true
        @stdout_reader = spawn_reader(stdout, :stdout) { @stdout_open = false }
        @stderr_reader = spawn_reader(stderr, :stderr) { @stderr_open = false }
      end
      @waiter = Thread.new do
        @exit_status = @wait_thread.value&.exitstatus
        @reader_done = true
      end
    end

    # Write to stdin without blocking. Returns false if the pipe is
    # already closed; otherwise true.
    def write(text)
      return false if @stdin.nil? || @stdin.closed?

      @stdin.write(text)
      true
    rescue Errno::EPIPE, IOError
      false
    end

    def close_stdin
      @stdin&.close unless @stdin&.closed?
    rescue IOError
      # Already closed.
    end

    # Pop everything available without blocking. Returns
    # Array<[stream_sym, payload]> where stream_sym is :stdout /
    # :stderr / :close and payload is a line string (no trailing
    # newline) or the stream symbol for :close.
    def drain
      out = []
      out << @queue.pop(true) until @queue.empty?
      out
    rescue ThreadError
      out
    end

    # True once the process exited AND every line has been drained
    # AND both readers signaled EOF. Callers can safely finalize.
    def done?
      @reader_done && @queue.empty? && !@stdout_open && !@stderr_open
    end

    def alive?
      @wait_thread&.alive?
    end

    # Send a signal. SIGTERM by default; if the process is still
    # alive 100ms later, escalate to SIGKILL.
    def kill(signal = 'TERM')
      return if @wait_thread.nil?
      return unless alive?

      @killed = true
      Process.kill(signal, @wait_thread.pid)
      return if signal == 'KILL'

      Thread.new do
        sleep 0.1
        Process.kill('KILL', @wait_thread.pid) if alive?
      rescue Errno::ESRCH
        # Already gone.
      end
    rescue Errno::ESRCH
      # Already exited.
    end

    def pid
      @wait_thread&.pid
    end

    private def build_argv
      if @cmd.is_a?(Array)
        @cmd
      else
        # String: hand to shell -c. Default to /bin/sh when no shell
        # was passed.
        shell = (@shell.nil? || @shell.empty?) ? '/bin/sh' : @shell
        flag = (@shellcmdflag.nil? || @shellcmdflag.empty?) ? '-c' : @shellcmdflag
        [shell, flag, @cmd.to_s]
      end
    end

    private def spawn_reader(io, stream)
      Thread.new do
        io.each_line do |line|
          @queue << [stream, line.chomp]
        end
      rescue IOError
        # Pipe closed.
      ensure
        # Reader-side state flag — `done?` polls it. We don't push a
        # `:close` event onto the queue because no consumer needs it
        # and stale markers would defeat `@queue.empty?` checks.
        yield
        io.close unless io.closed?
      end
    end
  end
end
