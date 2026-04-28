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

        install_buffer_api(state, editor)

        # Build vim.api as a Lua table mapping nvim_* names to the bridges.
        state.eval(<<~LUA)
          vim.api = vim.api or {}
          vim.api.nvim_create_augroup       = _rvim_api_create_augroup
          vim.api.nvim_del_augroup_by_name  = _rvim_api_del_augroup_by_name
          vim.api.nvim_create_autocmd       = _rvim_api_create_autocmd

          vim.api.nvim_buf_get_lines        = _rvim_api_buf_get_lines
          vim.api.nvim_buf_set_lines        = _rvim_api_buf_set_lines
          vim.api.nvim_buf_get_name         = _rvim_api_buf_get_name
          vim.api.nvim_buf_set_name         = _rvim_api_buf_set_name
          vim.api.nvim_buf_line_count       = _rvim_api_buf_line_count
          vim.api.nvim_buf_get_option       = _rvim_api_buf_get_option
          vim.api.nvim_buf_set_option       = _rvim_api_buf_set_option
          vim.api.nvim_get_current_buf      = _rvim_api_get_current_buf
          vim.api.nvim_set_current_buf      = _rvim_api_set_current_buf
        LUA
      end

      def self.install_buffer_api(state, editor)
        resolve = ->(bufnr) { resolve_buffer(editor, bufnr) }

        state.function '_rvim_api_buf_get_lines' do |bufnr, start_idx, end_idx, _strict|
          buf = resolve.call(bufnr)
          next [] unless buf

          lines = buf.lines || []
          s = start_idx.to_i
          e = end_idx.to_i
          s = lines.size + s if s < 0
          e = lines.size + e + 1 if e < 0
          lines[s...e] || []
        end

        state.function '_rvim_api_buf_set_lines' do |bufnr, start_idx, end_idx, _strict, replacement|
          buf = resolve.call(bufnr)
          next nil unless buf

          lines = buf.lines || []
          s = start_idx.to_i
          e = end_idx.to_i
          s = lines.size + s if s < 0
          e = lines.size + e + 1 if e < 0
          new_lines = if replacement.respond_to?(:to_h)
                        replacement.to_h.values.map(&:to_s)
                      elsif replacement.is_a?(Array)
                        replacement.map(&:to_s)
                      else
                        []
                      end
          buf.lines = lines[0...s] + new_lines + (lines[e..] || [])
          if buf == editor.current_buffer
            editor.instance_variable_set(:@buffer_of_lines, buf.lines)
            editor.instance_variable_set(:@modified, true)
          end
        end

        state.function('_rvim_api_buf_get_name')   { |bufnr| (resolve.call(bufnr)&.filepath).to_s }
        state.function('_rvim_api_buf_set_name')   { |bufnr, name| buf = resolve.call(bufnr); buf.filepath = name.to_s if buf }
        state.function('_rvim_api_buf_line_count') { |bufnr| (resolve.call(bufnr)&.lines || []).size }

        state.function '_rvim_api_buf_get_option' do |bufnr, name|
          buf = resolve.call(bufnr)
          editor.settings.get(name.to_s, buffer: buf || :current)
        end

        state.function '_rvim_api_buf_set_option' do |bufnr, name, value|
          buf = resolve.call(bufnr)
          coerced = value.is_a?(Float) && value == value.to_i ? value.to_i : value
          editor.settings.set(name.to_s, coerced, buffer: buf)
        end

        state.function('_rvim_api_get_current_buf') { editor.current_buffer&.id || 0 }
        state.function '_rvim_api_set_current_buf' do |bufnr|
          buf = editor.buffers&.values&.find { |b| b.id == bufnr.to_i }
          editor.swap_to_buffer(buf) if buf
        end
      end

      def self.resolve_buffer(editor, bufnr)
        n = bufnr.to_i
        return editor.current_buffer if n.zero?

        editor.buffers&.values&.find { |b| b.id == n }
      end
    end
  end
end
