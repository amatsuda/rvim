# frozen_string_literal: true

require 'fileutils'

module Rvim
  module Lua
    # vim.loop / vim.uv — minimal libuv shim.
    #
    # Real libuv is an async event loop. We don't have one. What v3.12
    # ships:
    #
    #   - vim.loop.new_timer():start(timeout_ms, repeat_ms, cb) /:stop() /:close()
    #   - vim.defer_fn(fn, ms)  (sugar for one-shot timer)
    #   - vim.schedule(fn)       (run on next pump — ms=0 timer)
    #   - vim.loop.now()         (monotonic-ish)
    #   - vim.loop.hrtime()
    #
    # Timers fire when Editor#pump_lua_loop is called. The render loop
    # in Editor.start should call it once per iteration; for headless
    # use (tests, scripts), callers pump manually.
    module Loop
      module_function

      Timer = Struct.new(:id, :deadline_at, :repeat_ms, :callback, :stopped) do
        def fire_now?(now)
          !stopped && deadline_at <= now
        end
      end

      class Scheduler
        def initialize
          @timers = {}
          @next_id = 0
        end

        def add(timeout_ms, repeat_ms, callback)
          id = (@next_id += 1)
          @timers[id] = Timer.new(id, monotonic + (timeout_ms / 1000.0), repeat_ms, callback, false)
          id
        end

        def stop(id)
          t = @timers[id]
          t.stopped = true if t
        end

        def close(id)
          @timers.delete(id)
        end

        def pump
          now = monotonic
          fired = []
          @timers.each_value do |t|
            next unless t.fire_now?(now)

            fired << t
          end
          fired.each do |t|
            begin
              t.callback&.call
            rescue StandardError
              # Swallow — a misbehaving timer shouldn't kill the loop.
            end
            if t.repeat_ms.to_i.positive? && !t.stopped
              t.deadline_at = now + (t.repeat_ms / 1000.0)
            else
              @timers.delete(t.id)
            end
          end
          fired.size
        end

        def empty?
          @timers.empty?
        end

        private

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      def install(state, editor, _runtime)
        scheduler = Scheduler.new
        editor.instance_variable_set(:@lua_scheduler, scheduler)

        state.function('_rvim_loop_new_timer') { Object.new } # placeholder; the Lua side wraps via metatable below
        state.function '_rvim_loop_timer_start' do |timeout_ms, repeat_ms, cb|
          scheduler.add(timeout_ms.to_f, repeat_ms.to_f, cb)
        end
        state.function('_rvim_loop_timer_stop')  { |id| scheduler.stop(id.to_i) }
        state.function('_rvim_loop_timer_close') { |id| scheduler.close(id.to_i) }
        # Return as Float — Lua numbers are 64-bit doubles, but
        # rufus-lua converts Ruby Integers via a C int and overflows
        # past ~2³¹ (`integer too big to convert to 'int'`). Doubles
        # round-trip cleanly out to 2⁵³ which covers ~104 days of ns.
        state.function('_rvim_loop_now')         { Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000.0 }
        state.function('_rvim_loop_hrtime')      { Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000_000_000.0 }

        # fs_event handle API.
        state.function '_rvim_fs_event_start' do |path, opts, cb|
          opts_h = case opts
                   when Hash then opts
                   when nil then {}
                   else (opts.respond_to?(:to_h) ? opts.to_h : {})
                   end
          watcher = Rvim::FsWatcher.new(path.to_s, opts: opts_h)
          cb_lua = cb if cb.is_a?(Rufus::Lua::Function)
          # libuv-shape callback: (err, filename, events_table).
          wrapped = if cb_lua
                      ->(err, filename, events) { cb_lua.call(err, filename, events) }
                    end
          editor.fs_events.register(watcher, wrapped)
        end
        state.function('_rvim_fs_event_stop')  { |id| editor.fs_events.stop(id.to_i) }
        state.function('_rvim_fs_event_close') { |id| editor.fs_events.stop(id.to_i) }

        install_uv_spawn(state, editor)

        # Synchronous libuv-style filesystem ops. lazy.nvim and many
        # plugins call these without callbacks, expecting a return
        # value or nil on error.
        install_fs_sync(state)
        # File descriptors are integers everywhere except in Ruby
        # where IO objects own the int. We keep a fd → IO map.
        editor.instance_variable_set(:@lua_fs_fds, {}) unless editor.instance_variable_defined?(:@lua_fs_fds)
        install_fs_fd(state, editor)

        state.eval(<<~LUA)
          vim.loop = vim.loop or {}

          local function make_timer()
            local self = { _id = nil }
            function self:start(timeout, rep, cb)
              self._id = _rvim_loop_timer_start(timeout, rep, cb)
            end
            function self:stop()
              if self._id then _rvim_loop_timer_stop(self._id) end
            end
            function self:close()
              if self._id then _rvim_loop_timer_close(self._id); self._id = nil end
            end
            return self
          end

          vim.loop.new_timer = make_timer
          vim.loop.now    = _rvim_loop_now
          vim.loop.hrtime = _rvim_loop_hrtime

          -- libuv check / idle / prepare handles: phases of the event
          -- loop. We don't model phases distinctly — each becomes a
          -- 0-delay repeating timer that fires once per pump tick.
          -- lazy.nvim uses new_check to drain its async coroutine
          -- queue every iteration; a timer-as-check is functionally
          -- equivalent for our purposes.
          local function make_phase_handle()
            local self = { _id = nil, _cb = nil, _stopped = false }
            function self:start(cb)
              self._cb = cb
              self._stopped = false
              -- repeat every 0ms => fires every pump_lua_loop tick
              self._id = _rvim_loop_timer_start(0, 1, function()
                if not self._stopped and self._cb then self._cb() end
              end)
            end
            function self:stop()
              self._stopped = true
              if self._id then _rvim_loop_timer_stop(self._id) end
            end
            function self:close()
              if self._id then _rvim_loop_timer_close(self._id); self._id = nil end
            end
            function self:is_active() return self._id ~= nil and not self._stopped end
            return self
          end

          vim.loop.new_check   = make_phase_handle
          vim.loop.new_idle    = make_phase_handle
          vim.loop.new_prepare = make_phase_handle

          -- libuv-style spawn + pipes. Backed by Rvim::Job underneath;
          -- the Ruby side drains stdout/stderr each pump tick and
          -- routes lines to the registered pipe callbacks.
          local function make_pipe()
            local self = { _id = _rvim_uv_new_pipe(false), _closed = false }
            function self:read_start(cb)
              _rvim_uv_pipe_read_start(self._id, cb)
            end
            function self:read_stop()
              _rvim_uv_pipe_read_stop(self._id)
            end
            function self:write(data)
              _rvim_uv_pipe_write(self._id, data or "")
            end
            function self:close(_force)
              if not self._closed then
                self._closed = true
                _rvim_uv_pipe_close(self._id)
              end
            end
            function self:is_closing()
              return self._closed or _rvim_uv_pipe_is_closing(self._id)
            end
            function self:is_active() return not self._closed end
            return self
          end

          vim.loop.new_pipe = make_pipe

          function vim.loop.spawn(cmd, opts, on_exit)
            opts = opts or {}
            -- stdio entries can be pipe handles (with _id) or nil; we
            -- pass the underlying ids to Ruby. Lua tables only carry
            -- 1-based indexes so unwrap explicitly.
            local stdio_ids = {}
            local stdio = opts.stdio or {}
            for i = 1, 3 do
              local s = stdio[i]
              stdio_ids[i] = (type(s) == "table" and s._id) or s or false
            end
            local args = opts.args or {}
            local ruby_opts = {
              args = args, cwd = opts.cwd, env = opts.env,
              stdio = stdio_ids,
            }
            local res = _rvim_uv_spawn(cmd, ruby_opts, on_exit)
            -- res is { handle_id, pid }
            local hid = res[1] or res[1.0]
            local pid = res[2] or res[2.0]
            if not hid then return nil, nil end

            local handle = { _id = hid, _closed = false }
            function handle:close()
              if not self._closed then
                self._closed = true
                _rvim_uv_handle_close(self._id)
              end
            end
            function handle:is_closing() return self._closed end
            function handle:is_active()  return not self._closed end
            function handle:kill(sig) _rvim_uv_process_kill(self._id, sig or "TERM") end
            return handle, pid
          end

          function vim.loop.process_kill(handle, sig)
            if handle and handle._id then
              _rvim_uv_process_kill(handle._id, sig or "TERM")
            end
          end

          vim.uv = vim.loop  -- modern alias

          function vim.defer_fn(fn, ms)
            local t = vim.loop.new_timer()
            t:start(ms or 0, 0, function()
              fn()
              t:close()
            end)
          end

          function vim.schedule(fn)
            vim.defer_fn(fn, 0)
          end

          function vim.schedule_wrap(fn)
            return function(...)
              local args = {...}
              local n = select("#", ...)
              local _unpack = table.unpack or unpack
              vim.schedule(function() fn(_unpack(args, 1, n)) end)
            end
          end

          -- vim.uv.new_fs_event() — handle:start(path, opts, cb), :stop(), :close()
          local function make_fs_event()
            local self = { _id = nil }
            function self:start(path, opts, cb)
              self._id = _rvim_fs_event_start(path, opts or {}, cb)
              return self._id
            end
            function self:stop()
              if self._id then _rvim_fs_event_stop(self._id) end
            end
            function self:close()
              if self._id then _rvim_fs_event_close(self._id); self._id = nil end
            end
            return self
          end

          vim.loop.new_fs_event = make_fs_event
          -- vim.uv is the same table as vim.loop; new_fs_event reachable there too.

          -- ---- Filesystem ops (sync wrappers; callbacks ignored) -----
          vim.loop.fs_stat        = _rvim_fs_stat
          vim.loop.fs_lstat       = _rvim_fs_lstat
          vim.loop.fs_realpath    = _rvim_fs_realpath
          vim.loop.fs_scandir     = _rvim_fs_scandir
          -- Each call pops one [name, type] entry off the handle (a
          -- Lua array) and returns (name, type). nil signals EOF.
          vim.loop.fs_scandir_next = function(handle)
            if handle == nil or #handle == 0 then return nil end
            local entry = table.remove(handle, 1)
            if entry == nil then return nil end
            return entry[1], entry[2]
          end
          vim.loop.fs_mkdir       = _rvim_fs_mkdir
          vim.loop.fs_rmdir       = _rvim_fs_rmdir
          vim.loop.fs_unlink      = _rvim_fs_unlink
          vim.loop.fs_rename      = _rvim_fs_rename
          vim.loop.fs_access      = _rvim_fs_access
          vim.loop.fs_chmod       = _rvim_fs_chmod
          vim.loop.fs_open        = _rvim_fs_open
          vim.loop.fs_read        = _rvim_fs_read
          vim.loop.fs_write       = _rvim_fs_write
          vim.loop.fs_close       = _rvim_fs_close
          vim.loop.fs_copyfile    = _rvim_fs_copyfile
          vim.loop.cwd            = function() return _rvim_loop_cwd() end
          vim.loop.os_homedir     = function() return _rvim_loop_homedir() end
          vim.loop.os_uname       = _rvim_loop_uname
          vim.loop.os_getenv      = function(k) return _rvim_loop_getenv(k) end
          vim.loop.getpid         = function() return _rvim_loop_getpid() end

          -- vim.uv is the modern alias; everything reachable there.
          vim.uv = vim.loop
        LUA
      end

      # vim.loop.spawn + vim.loop.new_pipe — libuv-style async process
      # spawn. telescope and plenary's job module use this rather than
      # the higher-level jobstart/vim.system. We implement the minimal
      # surface that those plugins need: separate stdin/stdout/stderr
      # pipes, a read_start callback per pipe, process_kill, and an
      # on_exit callback. Backed by Rvim::Job (popen3 + thread-drained
      # queue); we route per-stream data into the registered pipe
      # callbacks every pump_lua_loop tick.
      def self.install_uv_spawn(state, editor)
        editor.instance_variable_set(:@lua_uv_pipes, {}) unless editor.instance_variable_defined?(:@lua_uv_pipes)
        editor.instance_variable_set(:@lua_uv_jobs,  {}) unless editor.instance_variable_defined?(:@lua_uv_jobs)
        editor.instance_variable_set(:@lua_uv_next_id, 0) unless editor.instance_variable_defined?(:@lua_uv_next_id)

        pipes = editor.instance_variable_get(:@lua_uv_pipes)
        jobs  = editor.instance_variable_get(:@lua_uv_jobs)
        alloc_id = lambda do
          n = editor.instance_variable_get(:@lua_uv_next_id) + 1
          editor.instance_variable_set(:@lua_uv_next_id, n)
          n
        end

        state.function('_rvim_uv_new_pipe') do |_ipc|
          id = alloc_id.call
          # `pending` holds bytes received from the job between
          # read_stop / read_start cycles. Telescope's LinesPipe
          # reads one chunk, calls read_stop, then read_start again —
          # without buffering we'd drop everything after the first
          # chunk.
          pipes[id] = {
            id: id, stream: nil, job_id: nil, cb: nil,
            closed: false, reading: false, pending: [], eof: false,
          }
          id
        end

        state.function '_rvim_uv_spawn' do |cmd, opts, on_exit|
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          args = lua_array_to_ruby(opts_h['args'])
          stdio = lua_array_to_ruby(opts_h['stdio'])
          # stdio is {stdin_pipe_id, stdout_pipe_id, stderr_pipe_id}.
          # Lua nil entries arrive as nil OR false (the Lua wrapper
          # substitutes false for nil because arrays can't hold nil).
          pipe_id = ->(v) { v.is_a?(Numeric) ? v.to_i : nil }
          stdin_pid  = pipe_id.call(stdio[0])
          stdout_pid = pipe_id.call(stdio[1])
          stderr_pid = pipe_id.call(stdio[2])

          job = Rvim::Job.new([cmd.to_s, *args.map(&:to_s)],
                              cwd: opts_h['cwd']&.to_s,
                              env: lua_hash_to_ruby(opts_h['env']))
          jobs[job.id] = {
            job: job,
            stdout_pid: stdout_pid,
            stderr_pid: stderr_pid,
            on_exit: on_exit.is_a?(Rufus::Lua::Function) ? on_exit : nil,
            exited: false,
          }
          pipes[stdout_pid][:stream] = :stdout if stdout_pid && pipes[stdout_pid]
          pipes[stdout_pid][:job_id] = job.id  if stdout_pid && pipes[stdout_pid]
          pipes[stderr_pid][:stream] = :stderr if stderr_pid && pipes[stderr_pid]
          pipes[stderr_pid][:job_id] = job.id  if stderr_pid && pipes[stderr_pid]
          pipes[stdin_pid][:stream]  = :stdin  if stdin_pid && pipes[stdin_pid]
          pipes[stdin_pid][:job_id]  = job.id  if stdin_pid && pipes[stdin_pid]
          job.start

          # Lua expects { handle_id, pid } — return as plain values; the
          # wrapper turns the handle_id into a table with methods.
          [job.id, job.pid || 0]
        end

        state.function '_rvim_uv_pipe_read_start' do |pid, cb|
          p = pipes[pid.to_i]
          if p
            p[:cb] = cb.is_a?(Rufus::Lua::Function) ? cb : nil
            p[:reading] = true
            # DON'T flush inline here. read_start can be called from
            # within a coroutine that's already running (telescope's
            # iter loop calls self:read() → read_start). If we delivered
            # buffered chunks now, the cb would call read_tx → saved_
            # callback → step → co.resume(thread) on a thread that's
            # already running, giving "cannot resume running coroutine".
            # Pending data gets delivered by the drainer on the next
            # pump_lua_loop tick instead.
          end
          0
        end

        state.function('_rvim_uv_pipe_read_stop') { |pid| (pipes[pid.to_i] || {})[:reading] = false; 0 }
        state.function '_rvim_uv_pipe_close' do |pid|
          p = pipes[pid.to_i]
          if p
            p[:closed] = true
            # Closing a stdin pipe must reach the underlying job so
            # commands like `cat` get an EOF and exit. Stdout/stderr
            # close is bookkeeping only — the reader threads will see
            # EOF when the child closes its end.
            if p[:stream] == :stdin && p[:job_id]
              entry = jobs[p[:job_id]]
              entry[:job].close_stdin if entry
            end
          end
          0
        end
        state.function('_rvim_uv_pipe_is_closing'){ |pid| ((pipes[pid.to_i] || {})[:closed]) == true }

        state.function '_rvim_uv_pipe_write' do |pid, data|
          p = pipes[pid.to_i]
          if p && p[:stream] == :stdin && p[:job_id]
            entry = jobs[p[:job_id]]
            entry[:job].write(data.to_s) if entry
          end
          0
        end

        state.function '_rvim_uv_process_kill' do |hid, signal|
          entry = jobs[hid.to_i]
          entry[:job].kill(signal.to_s.empty? ? 'TERM' : signal.to_s) if entry
          0
        end

        state.function '_rvim_uv_handle_close' do |hid|
          entry = jobs[hid.to_i]
          entry[:job].kill('TERM') if entry && !entry[:exited]
          0
        end

        # Register a drain hook the editor's main loop will call.
        editor.instance_variable_set(:@lua_uv_drainer, lambda do
          jobs.dup.each do |jid, entry|
            job = entry[:job]
            # Move job-queue lines into per-pipe pending buffers, then
            # flush each pipe to its callback if it's currently
            # reading. Buffering means read_stop/read_start cycles
            # never drop data.
            job.drain.each do |stream, line|
              pid = stream == :stdout ? entry[:stdout_pid] : entry[:stderr_pid]
              p = pid && pipes[pid]
              next unless p && !p[:closed]

              p[:pending] << (line + "\n")
            end

            [entry[:stdout_pid], entry[:stderr_pid]].compact.each do |epid|
              p = pipes[epid]
              flush_pending_to_cb(p) if p && !p[:closed]
            end

            next unless job.done? && !entry[:exited]

            entry[:exited] = true
            [entry[:stdout_pid], entry[:stderr_pid]].compact.each do |epid|
              p = pipes[epid]
              next unless p && !p[:closed]

              p[:eof] = true
              flush_pending_to_cb(p) # may deliver final nil
            end
            if (cb = entry[:on_exit])
              code = job.exit_status || 0
              begin
                cb.call(code, 0)
              rescue StandardError
              end
            end
          end
        end)
      end

      # Deliver at most ONE chunk per call. The callback can re-enter
      # read_start (telescope's iter does this on every read), which
      # would otherwise recursively try to resume the same Lua
      # coroutine the callback is already executing inside. One chunk
      # per pump tick avoids the recursion entirely; the next pump
      # picks up where we left off.
      def self.flush_pending_to_cb(p)
        return unless p[:cb] && p[:reading] && !p[:closed]

        if !p[:pending].empty?
          chunk = p[:pending].shift
          begin
            p[:cb].call(nil, chunk)
          rescue StandardError
            # plugin-side bug — keep the loop alive
          end
          return
        end

        return unless p[:eof] && p[:pending].empty? && p[:cb] && p[:reading] && !p[:closed]

        begin
          p[:cb].call(nil, nil)
        rescue StandardError
        end
        p[:eof] = false
      end

      def self.lua_array_to_ruby(v)
        return [] if v.nil?
        return v if v.is_a?(Array)

        if v.respond_to?(:to_h)
          h = v.to_h
          return [] if h.empty?

          (1..h.size).map { |i| h[i] || h[i.to_f] }
        else
          []
        end
      end

      def self.lua_hash_to_ruby(v)
        return nil if v.nil?
        return v if v.is_a?(Hash)

        v.respond_to?(:to_h) ? v.to_h : nil
      end

      def self.install_fs_sync(state)
        state.function('_rvim_fs_stat')      { |path| fs_stat_table(File.stat(path.to_s)) rescue nil }
        state.function('_rvim_fs_lstat')     { |path| fs_stat_table(File.lstat(path.to_s)) rescue nil }
        state.function('_rvim_fs_realpath')  { |path| File.realpath(path.to_s) rescue nil }
        # Scandir handle: we return a Ruby Array<[name, type]>; the
        # Lua wrapper's scandir_next walks it via an index closure.
        state.function '_rvim_fs_scandir' do |path|
          base = path.to_s
          Dir.children(base).map do |name|
            full = File.join(base, name)
            type = entry_type(full)
            [name, type]
          end
        rescue StandardError
          nil
        end
        # scandir_next is a Lua-side pop on the array — see the
        # wrapper in the state.eval block.
        state.function '_rvim_fs_mkdir' do |path, mode|
          Dir.mkdir(path.to_s, (mode || 0o755).to_i)
          true
        rescue StandardError
          false
        end
        state.function '_rvim_fs_rmdir' do |path|
          Dir.rmdir(path.to_s)
          true
        rescue StandardError
          false
        end
        state.function '_rvim_fs_unlink' do |path|
          File.unlink(path.to_s)
          true
        rescue StandardError
          false
        end
        state.function '_rvim_fs_rename' do |old, new|
          File.rename(old.to_s, new.to_s)
          true
        rescue StandardError
          false
        end
        state.function '_rvim_fs_access' do |path, _mode|
          File.exist?(path.to_s)
        end
        state.function '_rvim_fs_chmod' do |path, mode|
          File.chmod(mode.to_i, path.to_s)
          true
        rescue StandardError
          false
        end
        state.function '_rvim_fs_copyfile' do |src, dst, _opts|
          FileUtils.cp(src.to_s, dst.to_s)
          true
        rescue StandardError
          false
        end
        state.function('_rvim_loop_cwd')     { Dir.pwd }
        state.function('_rvim_loop_homedir') { ENV['HOME'] || Dir.home }
        state.function '_rvim_loop_uname' do
          {
            'sysname'  => `uname -s`.strip,
            'release'  => `uname -r`.strip,
            'machine'  => `uname -m`.strip,
            'version'  => `uname -v`.strip[0..120],
          }
        rescue StandardError
          { 'sysname' => 'Unknown', 'release' => '', 'machine' => '', 'version' => '' }
        end
        state.function('_rvim_loop_getenv')  { |k| ENV[k.to_s] }
        state.function('_rvim_loop_getpid')  { Process.pid }
      end

      def self.install_fs_fd(state, editor)
        fds = editor.instance_variable_get(:@lua_fs_fds)
        next_fake = [1000]
        state.function '_rvim_fs_open' do |path, flags_str, _mode|
          flag_map = { 'r' => 'r', 'w' => 'w', 'a' => 'a', 'r+' => 'r+', 'w+' => 'w+' }
          mode = flag_map[flags_str.to_s] || 'r'
          io = File.open(path.to_s, mode)
          fd = (next_fake[0] += 1)
          fds[fd] = io
          fd
        rescue StandardError
          nil
        end
        state.function '_rvim_fs_read' do |fd, length, offset|
          io = fds[fd.to_i]
          next nil unless io

          io.seek(offset.to_i) if offset
          io.read(length.to_i)
        rescue StandardError
          nil
        end
        state.function '_rvim_fs_write' do |fd, data, offset|
          io = fds[fd.to_i]
          next 0 unless io

          io.seek(offset.to_i) if offset
          io.write(data.to_s)
        rescue StandardError
          0
        end
        state.function '_rvim_fs_close' do |fd|
          io = fds.delete(fd.to_i)
          io&.close
          true
        rescue StandardError
          false
        end
      end

      def self.fs_stat_table(s)
        {
          'type'  => stat_type(s),
          'size'  => s.size,
          'mtime' => { 'sec' => s.mtime.to_i, 'nsec' => s.mtime.nsec },
          'atime' => { 'sec' => s.atime.to_i, 'nsec' => s.atime.nsec },
          'ctime' => { 'sec' => s.ctime.to_i, 'nsec' => s.ctime.nsec },
          'mode'  => s.mode,
          'uid'   => s.uid,
          'gid'   => s.gid,
          'ino'   => s.ino,
          'nlink' => s.nlink,
        }
      end

      def self.stat_type(s)
        return 'directory' if s.directory?
        return 'file' if s.file?
        return 'link' if s.symlink?
        return 'fifo' if s.pipe?
        return 'socket' if s.socket?
        return 'char' if s.chardev?
        return 'block' if s.blockdev?

        'unknown'
      end

      def self.entry_type(path)
        s = File.lstat(path)
        stat_type(s)
      rescue StandardError
        'unknown'
      end
    end
  end
end
