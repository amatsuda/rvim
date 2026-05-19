# frozen_string_literal: true

module Rvim
  module Lua
    # vim.fn.jobstart / jobsend / jobstop / jobwait — NeoVim's
    # job-control family.
    # vim.system(cmd, opts, on_exit)                — one-shot wrapper.
    # vim.wait(ms, predicate, interval)             — blocking pump.
    #
    # Subprocesses spawn via Rvim::Job; callbacks fire on the main
    # thread from Editor#pump_jobs (and from the inner pumps invoked
    # during vim.wait / vim.system :wait).
    module Job
      module_function

      def install(state, editor, _runtime)
        # --- jobstart ----------------------------------------------------
        state.function '_rvim_jobstart' do |cmd, opts|
          opts_h = lua_hash(opts)
          job = build_job(cmd, opts_h, editor)
          editor.jobs.register(
            job,
            on_stdout: wrap_callback(opts_h['on_stdout']),
            on_stderr: wrap_callback(opts_h['on_stderr']),
            on_exit:   wrap_callback(opts_h['on_exit']),
          )
        end

        state.function('_rvim_jobsend')  { |id, data| editor.jobs.write(id.to_i, normalize_text(data)) }
        state.function('_rvim_jobstop')  { |id|       editor.jobs.stop(id.to_i) }
        state.function '_rvim_jobwait' do |ids, timeout|
          ids_arr = lua_array(ids).map(&:to_i)
          # NeoVim's jobwait: -1 (or nil) means "no timeout".
          t = timeout.nil? ? nil : timeout.to_i
          t = nil if t == -1
          editor.jobs.wait(ids_arr, t)
        end

        # --- vim.system one-shot wrapper --------------------------------
        state.function '_rvim_system' do |cmd, opts, on_exit|
          opts_h = lua_hash(opts)
          stdout = +''
          stderr = +''
          job = build_job(cmd, opts_h, editor)
          cb_exit = wrap_callback(on_exit)
          id = editor.jobs.register(
            job,
            on_stdout: ->(_id, data, _) { stdout << data.join("\n") << "\n" unless data.empty? },
            on_stderr: ->(_id, data, _) { stderr << data.join("\n") << "\n" unless data.empty? },
            on_exit:   lambda do |_id, code_arr, _|
              code = code_arr.first.to_i
              cb_exit&.call(_id, [{ 'code' => code, 'stdout' => stdout, 'stderr' => stderr }], 'exit')
            end,
          )
          # Feed stdin once at start if requested.
          opts_text = opts_h['stdin']
          if opts_text
            job.write(opts_text.to_s)
            job.close_stdin
          end
          id
        end

        # --- vim.wait ---------------------------------------------------
        state.function '_rvim_wait' do |ms, predicate, interval|
          predicate_fn = predicate.is_a?(Rufus::Lua::Function) ? predicate : nil
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (ms.to_f / 1000.0)
          tick = ((interval || 200).to_f / 1000.0)
          loop do
            if predicate_fn
              hit = false
              begin
                hit = predicate_fn.call
              rescue StandardError
                hit = false
              end
              break true if hit
            end
            break false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

            pump_event_loop(editor)
            sleep tick
          end
        end

        state.eval(<<~LUA)
          vim.fn = vim.fn or {}
          vim.fn.jobstart = function(cmd, opts) return _rvim_jobstart(cmd, opts or {}) end
          vim.fn.jobsend  = function(id, data) return _rvim_jobsend(id, data) end
          vim.fn.jobstop  = function(id) return _rvim_jobstop(id) end
          vim.fn.jobwait  = function(ids, timeout) return _rvim_jobwait(ids, timeout) end

          function vim.system(cmd, opts, on_exit) return _rvim_system(cmd, opts or {}, on_exit) end
          function vim.wait(ms, predicate, interval) return _rvim_wait(ms, predicate, interval) end
        LUA
      end

      # ----- helpers --------------------------------------------------

      def lua_hash(value)
        case value
        when Hash then value
        when nil then {}
        else (value.respond_to?(:to_h) ? value.to_h : {})
        end
      end

      def lua_array(value)
        case value
        when Array then value
        when nil then []
        when Hash then value.values
        else (value.respond_to?(:to_a) ? value.to_a : [])
        end
      end

      def normalize_text(data)
        if data.is_a?(Array)
          "#{data.join("\n")}\n"
        else
          lua_array(data).map(&:to_s).then do |arr|
            arr.empty? ? data.to_s : "#{arr.join("\n")}\n"
          end
        end
      end

      def wrap_callback(fn)
        return nil unless fn.is_a?(Rufus::Lua::Function)

        # Lua callbacks expect (id, data_table, name). data is an
        # Array<String>; rufus-lua surfaces Ruby Array as a Lua
        # array-like table automatically.
        ->(id, data, name) { fn.call(id, data, name) }
      end

      def build_job(cmd, opts_h, editor)
        argv = if cmd.is_a?(Array)
                 cmd
               elsif cmd.respond_to?(:to_h) && cmd.to_h.values.all?
                 cmd.to_h.values.map(&:to_s)
               else
                 cmd.to_s
               end
        env = lua_hash(opts_h['env']).transform_keys(&:to_s).transform_values(&:to_s)
        env = nil if env.empty?
        cwd = opts_h['cwd']&.to_s
        Rvim::Job.new(argv,
                      shell: editor.settings.get(:shell).to_s,
                      shellcmdflag: editor.settings.get(:shellcmdflag).to_s,
                      env: env,
                      cwd: cwd)
      end

      def pump_event_loop(editor)
        editor.pump_jobs       if editor.respond_to?(:pump_jobs)
        editor.pump_lua_loop   if editor.respond_to?(:pump_lua_loop)
        editor.pump_async_commands if editor.respond_to?(:pump_async_commands)
        editor.lsp.pump if editor.respond_to?(:lsp) && editor.lsp.respond_to?(:pump)
      rescue StandardError
        nil
      end
    end
  end
end
