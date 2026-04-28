# frozen_string_literal: true

module Rvim
  module Lua
    # Configures Lua's package.path so require('foo.bar') walks &runtimepath
    # looking for lua/foo/bar.lua and lua/foo/bar/init.lua, mirroring NeoVim's
    # behavior. We refresh package.path lazily before any require by replacing
    # it on each install — for v3.5 a single-shot at runtime startup is
    # sufficient since runtimepath rarely changes mid-session, but :runtime/
    # :packadd are also expected to refresh it (handled in a small hook).
    module Loader
      module_function

      def install(state, editor, _runtime)
        refresh(state, editor)

        # vim.loader stub — modern NeoVim exposes a loader cache; plugins
        # probe for it but the few that hard-fail when missing are rare.
        state.eval(<<~LUA)
          vim.loader = vim.loader or {
            enable = function() end,
            disable = function() end,
            reset = function() end,
          }
        LUA
      end

      def refresh(state, editor)
        rtp = editor.settings.get(:runtimepath).to_s.split(',').map { |p| File.expand_path(p.strip) }.reject(&:empty?)
        entries = rtp.flat_map do |dir|
          [
            File.join(dir, 'lua', '?.lua'),
            File.join(dir, 'lua', '?', 'init.lua'),
          ]
        end
        return if entries.empty?

        # Prepend our entries so user runtimepath beats the system path.
        path_str = entries.join(';')
        state.eval(<<~LUA)
          package.path = #{path_str.inspect} .. ';' .. (package.path or '')
        LUA
      end
    end
  end
end
