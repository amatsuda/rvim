# frozen_string_literal: true

module Rvim
  module Lua
    # vim.api.nvim_*  — the namespaced API that Lua plugins target.
    #
    # v3.4 introduces this module with the autocmd subset; later ships
    # add buffer/window/exec/eval functions.
    module Api
      module_function

      def install(state, editor, _runtime)
        # Augroup registry: name -> integer id, persisted on the editor side.
        editor.instance_variable_set(:@lua_augroups, {}) unless editor.instance_variable_defined?(:@lua_augroups)
        augroups = editor.instance_variable_get(:@lua_augroups)
        next_group_id = [0]

        state.function '_rvim_api_create_augroup' do |name, opts|
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          if augroups.key?(name.to_s) && opts_h['clear'] != false
            editor.autocommands.clear_group(augroups[name.to_s])
          end
          unless augroups.key?(name.to_s)
            next_group_id[0] += 1
            augroups[name.to_s] = next_group_id[0]
          end
          augroups[name.to_s]
        end

        state.function '_rvim_api_del_augroup_by_name' do |name|
          gid = augroups.delete(name.to_s)
          editor.autocommands.clear_group(gid) if gid
        end

        state.function '_rvim_api_create_autocmd' do |events, opts|
          events_arr = if events.respond_to?(:to_h)
                         events.to_h.values.map(&:to_s)
                       else
                         [events.to_s]
                       end
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          patterns_raw = opts_h['pattern']
          patterns = if patterns_raw.respond_to?(:to_h)
                       patterns_raw.to_h.values.map(&:to_s)
                     elsif patterns_raw.nil? || patterns_raw == ''
                       ['*']
                     else
                       [patterns_raw.to_s]
                     end
          group_id = case opts_h['group']
                     when nil then nil
                     when Numeric then opts_h['group'].to_i
                     else augroups[opts_h['group'].to_s]
                     end

          callback = nil
          command = ''
          if opts_h['callback'].is_a?(Rufus::Lua::Function)
            cb_lua = opts_h['callback']
            callback = ->(args) { cb_lua.call(args) }
          elsif opts_h['command']
            command = opts_h['command'].to_s
          end

          editor.autocommands.add(events_arr, patterns, command, callback: callback, group: group_id)
        end

        # Build vim.api as a Lua table mapping nvim_* names to the bridges.
        state.eval(<<~LUA)
          vim.api = vim.api or {}
          vim.api.nvim_create_augroup       = _rvim_api_create_augroup
          vim.api.nvim_del_augroup_by_name  = _rvim_api_del_augroup_by_name
          vim.api.nvim_create_autocmd       = _rvim_api_create_autocmd
        LUA
      end
    end
  end
end
