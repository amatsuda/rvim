# frozen_string_literal: true

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
        LUA
      end
    end
  end
end
