# frozen_string_literal: true

module Rvim
  module Lua
    # One Lua VM per Editor. Wraps Rufus::Lua::State and registers the `vim`
    # global. If the rufus-lua gem or a Lua 5.1-compatible dynamic library
    # isn't available, every public method becomes a no-op that surfaces a
    # status_message — the editor stays usable, only Lua features are off.
    class Runtime
      LIBRARY_CANDIDATES = [
        ENV['LUA_LIB'],
        '/opt/homebrew/opt/luajit/lib/libluajit-5.1.dylib',
        '/usr/local/opt/luajit/lib/libluajit-5.1.dylib',
        '/opt/homebrew/lib/libluajit-5.1.dylib',
        '/usr/local/lib/libluajit-5.1.dylib',
        '/opt/homebrew/lib/liblua5.1.dylib',
        '/usr/local/lib/liblua5.1.dylib',
        '/usr/lib/x86_64-linux-gnu/libluajit-5.1.so.2',
        '/usr/lib/liblua5.1.so',
      ].compact.freeze

      class << self
        def available?
          ensure_loaded
          @available == true
        end

        def unavailable_reason
          ensure_loaded
          @unavailable_reason
        end

        private

        def ensure_loaded
          return if defined?(@available)

          @available = false
          @unavailable_reason = nil

          lib = LIBRARY_CANDIDATES.find { |p| p && File.exist?(p) }
          unless lib
            @unavailable_reason = "no Lua 5.1 dylib found (install luajit, e.g. `brew install luajit`)"
            return
          end

          ENV['LUA_LIB'] ||= lib

          begin
            require 'rufus-lua'
            patch_stack_push!
            patch_function_call!
            @available = true
          rescue LoadError => e
            @unavailable_reason = "rufus-lua gem not loadable: #{e.message}"
          rescue => e
            @unavailable_reason = "Lua initialization failed: #{e.message}"
          end
        end

        # Rufus::Lua::StateMixin#stack_push errors on Rufus::Lua::Table
        # ("don't know how to pass Ruby instance of Rufus::Lua::Table
        # to Lua"). That hits whenever a Ruby callback stored a Lua
        # table (e.g. vim.g.foo = {1,2}) and a later getter returns
        # it. Wrap stack_push once at load time to walk the value and
        # demote any Rufus::Lua::Table to a plain Ruby Hash/Array
        # before pushing.
        def patch_stack_push!
          return if Rufus::Lua::StateMixin.private_method_defined?(:_rvim_orig_stack_push)

          mod = Module.new do
            def _rvim_demote(v)
              if defined?(Rufus::Lua::Table) && v.is_a?(Rufus::Lua::Table)
                h = v.to_h
                keys = h.keys
                if !keys.empty? && keys.all? { |k| k.is_a?(Numeric) }
                  (1..h.size).map { |i| _rvim_demote(h[i] || h[i.to_f]) }
                else
                  h.each_with_object({}) { |(k, val), acc| acc[k.to_s] = _rvim_demote(val) }
                end
              elsif v.is_a?(Hash)
                v.each_with_object({}) { |(k, val), acc| acc[k] = _rvim_demote(val) }
              elsif v.is_a?(Array)
                v.map { |val| _rvim_demote(val) }
              else
                v
              end
            end

            def stack_push(o)
              super(_rvim_demote(o))
            end
          end
          Rufus::Lua::StateMixin.prepend(mod)
          Rufus::Lua::StateMixin.alias_method(:_rvim_orig_stack_push, :stack_push)
        end

        # Rufus::Lua::Function pins @pointer to the lua_State* that was
        # active when the Function was constructed. When state.function
        # dispatches a Ruby callback from inside a coroutine T1, any
        # Function arg (e.g. `step` passed to vim.schedule, or the cb
        # passed to read_start) captures T1's pointer. Calling that
        # Function LATER from the drainer's pump runs Lua code ON T1's
        # state — coroutine.running() returns T1, and the Function's
        # body calling co.resume(T1) fails with "cannot resume running
        # coroutine" because T1 IS currently running.
        #
        # The Lua registry is shared across coroutines, so the @ref is
        # valid from any state. Swap @pointer to the main state for the
        # duration of the call; coroutine.running() then correctly
        # returns nil (we're on the main thread) and resumes work.
        def patch_function_call!
          return if Rufus::Lua::Function.private_method_defined?(:_rvim_orig_call)

          mod = Module.new do
            def call(*args)
              main = Rvim::Lua::Runtime.main_state_pointer
              if main && @pointer != main
                saved = @pointer
                @pointer = main
                begin
                  super
                ensure
                  @pointer = saved
                end
              else
                super
              end
            end
          end
          Rufus::Lua::Function.prepend(mod)
          Rufus::Lua::Function.alias_method(:_rvim_orig_call, :call)
        end
      end

      # Captured when the per-editor Rufus::Lua::State is constructed.
      # Used by the Function#call patch above.
      class << self
        attr_accessor :main_state_pointer
      end

      attr_reader :editor, :state
      attr_accessor :captured_print

      def initialize(editor)
        @editor = editor
        @state = nil
        @callbacks = {} # id => Lua function ref
        @next_callback_id = 0
        @initialized = false
      end

      def available?
        self.class.available?
      end

      def state
        return nil unless available?

        @state ||= begin
          s = Rufus::Lua::State.new
          self.class.main_state_pointer = s.instance_variable_get(:@pointer)
          Rvim::Lua::Bridge.install(s, @editor, self)
          s
        end
      end

      def eval(code)
        unless available?
          @editor.status_message = "Lua disabled: #{self.class.unavailable_reason}"
          return nil
        end

        state.eval(code)
      rescue Rufus::Lua::LuaError => e
        @editor.status_message = "E5108: Lua: #{e.message}"
        nil
      rescue => e
        @editor.status_message = "E5108: Lua error: #{e.message}"
        nil
      end

      def load_file(path)
        unless File.file?(path)
          @editor.status_message = "E484: Can't open file #{path}"
          return nil
        end

        eval(File.read(path))
      end

      # Callback registry: keep Ruby-side refs to Lua functions so they can be
      # invoked later (e.g. autocmd handlers).
      def register_callback(lua_fn)
        id = (@next_callback_id += 1)
        @callbacks[id] = lua_fn
        id
      end

      def call_callback(id, *args)
        fn = @callbacks[id]
        return nil unless fn

        fn.call(*args)
      rescue => e
        @editor.status_message = "E5108: Lua callback error: #{e.message}"
        nil
      end

      def remove_callback(id)
        @callbacks.delete(id)
      end
    end
  end
end
