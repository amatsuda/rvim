# frozen_string_literal: true

module Rvim
  module Lua
    # Builds the `vim` global table on a freshly-created Lua state. Each
    # namespace lives in its own file under lib/rvim/lua/. This top-level
    # bridge orchestrates the install, calling each namespace's `install`
    # method in turn.
    module Bridge
      module_function

      NAMESPACES = %i[cmd notify].freeze

      def install(state, editor, runtime)
        # Create empty `vim` global as a Ruby Hash bridged to a Lua table.
        # Rufus-lua exposes hashes back as Lua tables when assigned to globals.
        state.eval('vim = {}')

        Rvim::Lua::Cmd.install(state, editor, runtime)
        Rvim::Lua::Notify.install(state, editor, runtime)
        Rvim::Lua::Opt.install(state, editor, runtime)
        Rvim::Lua::Vars.install(state, editor, runtime)
        Rvim::Lua::Keymap.install(state, editor, runtime)
        Rvim::Lua::Api.install(state, editor, runtime)
        Rvim::Lua::Loader.install(state, editor, runtime)
        Rvim::Lua::Fn.install(state, editor, runtime)
        Rvim::Lua::Util.install(state, editor, runtime)
        Rvim::Lua::Ui.install(state, editor, runtime)
        Rvim::Lua::Loop.install(state, editor, runtime)
        Rvim::Lua::Job.install(state, editor, runtime)
        Rvim::Lua::LspStub.install(state, editor, runtime)
        Rvim::Lua::Fs.install(state, editor, runtime)
        Rvim::Lua::Json.install(state, editor, runtime)

        # Redirect Lua's `print` into the editor's message buffer so
        # output from `:lua print(...)` survives the next render
        # tick. The `:lua` command handler reads `runtime.captured_print`
        # after evaluating the chunk and pages it via show_list,
        # matching NeoVim's "Press ENTER" behaviour.
        state.function('_rvim_lua_print') do |line|
          (runtime.captured_print ||= []) << line.to_s
        end
        state.eval(<<~LUA)
          local _tostring = tostring
          print = function(...)
            local n = select("#", ...)
            local parts = {}
            for i = 1, n do parts[i] = _tostring(select(i, ...)) end
            _rvim_lua_print(table.concat(parts, "\\t"))
          end
        LUA
      end
    end
  end
end
