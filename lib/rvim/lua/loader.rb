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

        # vim.loader — NeoVim 0.9+ module-cache facade. Lazy.nvim
        # substitutes its lazy.core.cache for this on >=0.9.1, so we
        # need a working `find` that:
        #   find(modname, opts)      -> { { modname, modpath }, ... }
        #   find("*", { all = true, paths = { dir } })
        #     -> every lua module under dir/lua/, recursively
        # Returns a flat string array [name1, path1, name2, path2, ...]
        # because rufus-lua can't push nested Ruby hashes back to Lua.
        # The Lua wrapper below pairs them up into {modname,modpath}.
        state.function '_rvim_loader_find_flat' do |modname, opts|
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          paths = collect_paths(editor, opts_h)
          all = opts_h['all'] == true
          loader_find(modname.to_s, paths, all: all).flat_map { |e| [e['modname'], e['modpath']] }
        end

        state.eval(<<~LUA)
          vim.loader = vim.loader or {}
          vim.loader.enable  = vim.loader.enable  or function() end
          vim.loader.disable = vim.loader.disable or function() end
          vim.loader.reset   = vim.loader.reset   or function() end
          vim.loader.find    = vim.loader.find    or function(modname, opts)
            local flat = _rvim_loader_find_flat(modname, opts or {})
            local out = {}
            for i = 1, #flat, 2 do
              table.insert(out, { modname = flat[i], modpath = flat[i + 1] })
            end
            return out
          end
          -- Some callers index .cache to disable individual entries.
          vim.loader.cache = vim.loader.cache or setmetatable({}, { __index = function() return nil end })
        LUA
      end

      def collect_paths(editor, opts_h)
        paths_raw = opts_h['paths']
        return [] if paths_raw.nil? && opts_h['rtp'] == false

        if paths_raw
          arr = if paths_raw.respond_to?(:to_h)
                  h = paths_raw.to_h
                  (1..h.size).map { |i| (h[i] || h[i.to_f]).to_s }
                elsif paths_raw.is_a?(Array)
                  paths_raw.map(&:to_s)
                else
                  [paths_raw.to_s]
                end
          return arr.reject(&:empty?)
        end

        editor.settings.get(:runtimepath).to_s.split(',').map(&:strip).reject(&:empty?)
      end

      def loader_find(modname, paths, all:)
        results = []
        paths.each do |base|
          lua_dir = File.join(base, 'lua')
          next unless File.directory?(lua_dir)

          if modname == '*'
            # Walk every .lua file under lua/, turn path into modname.
            Dir.glob(File.join(lua_dir, '**', '*.lua')).each do |p|
              rel = p.sub(%r{\A#{Regexp.escape(lua_dir)}/}, '')
              mod = rel.sub(/\.lua\z/, '').gsub('/', '.').sub(/\.init\z/, '')
              results << { 'modname' => mod, 'modpath' => p }
              return results unless all
            end
          else
            sub = modname.gsub('.', '/')
            [File.join(lua_dir, "#{sub}.lua"), File.join(lua_dir, sub, 'init.lua')].each do |cand|
              next unless File.file?(cand)

              results << { 'modname' => modname, 'modpath' => cand }
              return results unless all
            end
          end
        end
        results
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
