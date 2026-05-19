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
        state.function('_rvim_loop_now')         { (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i }
        state.function('_rvim_loop_hrtime')      { (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000_000_000).to_i }

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
