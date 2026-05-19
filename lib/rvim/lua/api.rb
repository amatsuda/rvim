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
        install_window_api(state, editor)
        install_extended_api(state, editor)

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

          vim.api.nvim_win_get_cursor       = _rvim_api_win_get_cursor
          vim.api.nvim_win_set_cursor       = _rvim_api_win_set_cursor
          vim.api.nvim_win_get_height       = _rvim_api_win_get_height
          vim.api.nvim_win_set_height       = _rvim_api_win_set_height
          vim.api.nvim_win_get_width        = _rvim_api_win_get_width
          vim.api.nvim_win_get_buf          = _rvim_api_win_get_buf
          vim.api.nvim_get_current_win      = _rvim_api_get_current_win

          vim.api.nvim_list_bufs            = _rvim_api_list_bufs
          vim.api.nvim_buf_is_valid         = _rvim_api_buf_is_valid
          vim.api.nvim_buf_is_loaded        = _rvim_api_buf_is_loaded
          vim.api.nvim_buf_get_var          = _rvim_api_buf_get_var
          vim.api.nvim_buf_set_var          = _rvim_api_buf_set_var
          vim.api.nvim_buf_del_var          = _rvim_api_buf_del_var
          vim.api.nvim_buf_get_changedtick  = _rvim_api_buf_get_changedtick

          vim.api.nvim_list_wins            = _rvim_api_list_wins
          vim.api.nvim_win_is_valid         = _rvim_api_win_is_valid

          vim.api.nvim_get_var              = _rvim_api_get_var
          vim.api.nvim_set_var              = _rvim_api_set_var
          vim.api.nvim_del_var              = _rvim_api_del_var
          vim.api.nvim_get_option           = _rvim_api_get_option
          vim.api.nvim_set_option           = _rvim_api_set_option
          vim.api.nvim_get_option_value     = _rvim_api_get_option_value
          vim.api.nvim_set_option_value     = _rvim_api_set_option_value
          vim.api.nvim_get_mode             = _rvim_api_get_mode
          vim.api.nvim_command              = _rvim_api_command
          vim.api.nvim_echo                 = _rvim_api_echo
          vim.api.nvim_err_writeln          = _rvim_api_err_writeln
          vim.api.nvim_out_write            = _rvim_api_out_write
          vim.api.nvim_strwidth             = _rvim_api_strwidth
          vim.api.nvim_replace_termcodes    = _rvim_api_replace_termcodes
          vim.api.nvim_set_hl               = _rvim_api_set_hl

          -- Floating windows + scratch buffers.
          vim.api.nvim_create_buf           = _rvim_api_create_buf
          vim.api.nvim_open_win             = _rvim_api_open_win
          vim.api.nvim_win_close            = _rvim_api_win_close
          vim.api.nvim_win_get_config       = _rvim_api_win_get_config
          vim.api.nvim_win_set_config       = _rvim_api_win_set_config

          -- Buffer-local keymaps.
          vim.api.nvim_buf_set_keymap       = _rvim_api_buf_set_keymap
          vim.api.nvim_buf_del_keymap       = _rvim_api_buf_del_keymap
        LUA
      end

      def self.install_extended_api(state, editor)
        state.function('_rvim_api_list_bufs') { (editor.buffers&.values || []).map(&:id) }
        state.function('_rvim_api_buf_is_valid') { |bufnr| !resolve_buffer(editor, bufnr).nil? }
        state.function('_rvim_api_buf_is_loaded') { |bufnr| !resolve_buffer(editor, bufnr).nil? }

        state.function '_rvim_api_buf_get_var' do |bufnr, name|
          buf = resolve_buffer(editor, bufnr)
          buf&.vars&.[](name.to_s)
        end
        state.function '_rvim_api_buf_set_var' do |bufnr, name, value|
          buf = resolve_buffer(editor, bufnr)
          buf.vars[name.to_s] = value if buf
        end
        state.function '_rvim_api_buf_del_var' do |bufnr, name|
          buf = resolve_buffer(editor, bufnr)
          buf.vars.delete(name.to_s) if buf
        end
        state.function '_rvim_api_buf_get_changedtick' do |bufnr|
          buf = resolve_buffer(editor, bufnr)
          # Approximate via undo history index when present.
          buf&.undo_redo_index.to_i
        end

        state.function('_rvim_api_list_wins') do
          all = (editor.windows || []) + (editor.respond_to?(:floating_windows) ? editor.floating_windows : [])
          all.map(&:id)
        end
        state.function('_rvim_api_win_is_valid') { |winid| !resolve_window(editor, winid).nil? }

        state.function('_rvim_api_get_var') { |name| editor.let_vars[name.to_s] }
        state.function('_rvim_api_set_var') { |name, value| editor.let_vars[name.to_s] = value }
        state.function('_rvim_api_del_var') { |name| editor.let_vars.delete(name.to_s) }

        state.function('_rvim_api_get_option') { |name| editor.settings.get(name.to_s) }
        state.function '_rvim_api_set_option' do |name, value|
          coerced = value.is_a?(Float) && value == value.to_i ? value.to_i : value
          editor.settings.set(name.to_s, coerced)
        end

        state.function '_rvim_api_get_option_value' do |name, opts|
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          if opts_h['buf']
            buf = resolve_buffer(editor, opts_h['buf'])
            editor.settings.get(name.to_s, buffer: buf || :current)
          else
            editor.settings.get(name.to_s)
          end
        end

        state.function '_rvim_api_set_option_value' do |name, value, opts|
          coerced = value.is_a?(Float) && value == value.to_i ? value.to_i : value
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          if opts_h['buf']
            buf = resolve_buffer(editor, opts_h['buf'])
            editor.settings.set(name.to_s, coerced, buffer: buf)
          else
            editor.settings.set(name.to_s, coerced)
          end
        end

        state.function '_rvim_api_get_mode' do
          { 'mode' => Rvim::Lua::Fn.mode(editor), 'blocking' => false }
        end

        state.function '_rvim_api_command' do |cmd|
          parsed = Rvim::Command.parse(cmd.to_s)
          Rvim::Command.execute(editor, parsed) if parsed
        end

        state.function('_rvim_api_echo') { |_chunks, history, _opts| editor.status_message = '' if history }
        state.function('_rvim_api_err_writeln') { |msg| editor.status_message = "ERR: #{msg}" }
        state.function('_rvim_api_out_write') { |msg| editor.status_message = msg.to_s }

        state.function('_rvim_api_strwidth') { |s| s.to_s.length }

        state.function '_rvim_api_replace_termcodes' do |s, _from_part, _do_lt, _special|
          Rvim::Keymap.expand(s.to_s, leader: editor.mapleader)
        end

        state.function '_rvim_api_set_hl' do |_ns_id, name, _val|
          # Highlight registry is mostly visual; for v1 stash the name so
          # plugins probing for highlights see them as defined.
          editor.instance_variable_get(:@lua_highlights) || editor.instance_variable_set(:@lua_highlights, {})
          editor.instance_variable_get(:@lua_highlights)[name.to_s] = true
        end

        install_float_api(state, editor)
        install_keymap_api(state, editor)
      end

      def self.install_keymap_api(state, editor)
        # nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts)
        state.function '_rvim_api_buf_set_keymap' do |bufnr, mode_arg, lhs, rhs, opts|
          buf = resolve_buffer(editor, bufnr)
          next unless buf

          modes = Rvim::Lua::Keymap.resolve_modes(mode_arg)
          expanded_lhs = Rvim::Keymap.expand(lhs.to_s, leader: editor.mapleader)
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          recursive = opts_h['noremap'] != true
          silent    = opts_h['silent'] == true
          callback  = opts_h['callback']
          if callback.is_a?(Rufus::Lua::Function)
            cb = -> { callback.call }
            buf.keymap.add(modes, expanded_lhs, '', recursive: recursive, silent: silent, callback: cb)
          else
            expanded_rhs = Rvim::Keymap.expand(rhs.to_s, leader: editor.mapleader)
            buf.keymap.add(modes, expanded_lhs, expanded_rhs, recursive: recursive, silent: silent)
          end
        end

        # nvim_buf_del_keymap(bufnr, mode, lhs)
        state.function '_rvim_api_buf_del_keymap' do |bufnr, mode_arg, lhs|
          buf = resolve_buffer(editor, bufnr)
          next unless buf

          modes = Rvim::Lua::Keymap.resolve_modes(mode_arg)
          expanded_lhs = Rvim::Keymap.expand(lhs.to_s, leader: editor.mapleader)
          buf.keymap.remove(modes, expanded_lhs) if buf.keymap?
        end
      end

      def self.install_float_api(state, editor)
        # nvim_create_buf(listed, scratch) -> bufnr
        state.function '_rvim_api_create_buf' do |listed, scratch|
          buf = Rvim::Buffer.new(editor.next_buffer_id_bump!, nil,
                                  encoding: editor.encoding,
                                  scratch: scratch == true,
                                  listed: listed == true)
          editor.register_buffer(buf)
          buf.id
        end

        # nvim_open_win(bufnr, enter, config) -> winid
        state.function '_rvim_api_open_win' do |bufnr, enter, config|
          buf = resolve_buffer(editor, bufnr)
          cfg = config.respond_to?(:to_h) ? config.to_h : {}
          win = editor.open_floating_window(buf, enter: enter == true, config: cfg)
          win.id
        end

        # nvim_win_close(winid, force)
        state.function '_rvim_api_win_close' do |winid, _force|
          win = resolve_window(editor, winid)
          if win&.floating?
            editor.close_floating_window(win)
          end
        end

        # nvim_win_get_config(winid) -> config table
        state.function '_rvim_api_win_get_config' do |winid|
          win = resolve_window(editor, winid)
          next {} unless win

          {
            'relative' => (win.floating? ? (win.relative || 'editor') : ''),
            'row'      => win.row,
            'col'      => win.col,
            'width'    => win.width,
            'height'   => win.height,
            'border'   => (win.border || :none).to_s,
            'focusable' => win.focusable,
            'zindex'   => win.zindex,
            'anchor'   => win.anchor,
            'title'    => win.title.to_s,
            'footer'   => win.footer.to_s,
            'hide'     => win.hide == true,
          }
        end

        # nvim_win_set_config(winid, config)
        state.function '_rvim_api_win_set_config' do |winid, config|
          win = resolve_window(editor, winid)
          cfg = config.respond_to?(:to_h) ? config.to_h : {}
          editor.apply_floating_config(win, cfg) if win
        end
      end

      def self.install_window_api(state, editor)
        resolve = ->(winid) { resolve_window(editor, winid) }

        state.function '_rvim_api_win_get_cursor' do |_winid|
          # NeoVim returns {row(1-based), col(0-based)}.
          [editor.line_index + 1, editor.byte_pointer]
        end

        state.function '_rvim_api_win_set_cursor' do |_winid, pos|
          arr = if pos.respond_to?(:to_h)
                  pos.to_h.values
                elsif pos.is_a?(Array)
                  pos
                else
                  []
                end
          row = arr[0].to_i - 1
          col = arr[1].to_i
          editor.instance_variable_set(:@line_index, [[row, 0].max, [editor.buffer_of_lines.size - 1, 0].max].min)
          editor.instance_variable_set(:@byte_pointer, [col, 0].max)
        end

        state.function('_rvim_api_win_get_height') { |winid| (resolve.call(winid)&.height) || 24 }
        state.function('_rvim_api_win_set_height') { |winid, h| w = resolve.call(winid); w.height = h.to_i if w }
        state.function('_rvim_api_win_get_width')  { |winid| (resolve.call(winid)&.width) || 80 }
        state.function('_rvim_api_win_get_buf')    { |winid| resolve.call(winid)&.buffer&.id || 0 }
        state.function('_rvim_api_get_current_win') { editor.current_window&.id || 0 }
      end

      def self.resolve_window(editor, winid)
        n = winid.to_i
        return editor.current_window if n.zero?

        # Each Window now carries a stable id (Window#id) so floats
        # and tiled windows live in the same namespace.
        all = (editor.windows || []) + (editor.respond_to?(:floating_windows) ? editor.floating_windows : [])
        all.find { |w| w.id == n } || editor.current_window
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
