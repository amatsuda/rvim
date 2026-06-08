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
          events_arr = if events.is_a?(Rufus::Lua::Table)
                         events.to_h.values.map(&:to_s)
                       else
                         [events.to_s]
                       end
          opts_h = opts.is_a?(Rufus::Lua::Table) ? opts.to_h : {}
          patterns_raw = opts_h['pattern']
          # Don't lean on respond_to?(:to_h) here — `nil.to_h` returns
          # {} on modern Ruby (and `"foo".respond_to?(:to_h)` flips by
          # version), so the nil/empty-pattern case has to come first
          # or it gets routed through the empty-table branch and we
          # add zero entries instead of defaulting to '*'.
          patterns = if patterns_raw.nil? || patterns_raw == ''
                       ['*']
                     elsif patterns_raw.is_a?(Rufus::Lua::Table)
                       patterns_raw.to_h.values.map(&:to_s)
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
        install_user_command_api(state, editor)
        install_keymap_introspection_api(state, editor)
        install_runtime_api(state, editor)
        install_global_keymap_api(state, editor)
        install_exec_api(state, editor)
        install_exec_autocmds_api(state, editor)

        # Build vim.api as a Lua table mapping nvim_* names to the bridges.
        state.eval(<<~LUA)
          vim.api = vim.api or {}
          vim.api.nvim_create_augroup       = _rvim_api_create_augroup
          vim.api.nvim_del_augroup_by_name  = _rvim_api_del_augroup_by_name
          vim.api.nvim_create_autocmd       = _rvim_api_create_autocmd

          vim.api.nvim_buf_get_lines        = _rvim_api_buf_get_lines
          vim.api.nvim_buf_set_lines        = _rvim_api_buf_set_lines
          vim.api.nvim_buf_set_text         = _rvim_api_buf_set_text
          vim.api.nvim_buf_delete           = _rvim_api_buf_delete
          vim.api.nvim_buf_get_name         = _rvim_api_buf_get_name
          vim.api.nvim_buf_set_name         = _rvim_api_buf_set_name
          vim.api.nvim_buf_line_count       = _rvim_api_buf_line_count
          vim.api.nvim_buf_get_option       = _rvim_api_buf_get_option
          vim.api.nvim_buf_set_option       = _rvim_api_buf_set_option
          vim.api.nvim_get_current_buf      = _rvim_api_get_current_buf
          vim.api.nvim_set_current_buf      = _rvim_api_set_current_buf
          vim.api.nvim_buf_call             = _rvim_api_buf_call

          vim.api.nvim_win_get_cursor       = _rvim_api_win_get_cursor
          vim.api.nvim_win_set_cursor       = _rvim_api_win_set_cursor
          vim.api.nvim_win_get_height       = _rvim_api_win_get_height
          vim.api.nvim_win_set_height       = _rvim_api_win_set_height
          vim.api.nvim_win_get_width        = _rvim_api_win_get_width
          vim.api.nvim_win_set_width        = _rvim_api_win_set_width
          vim.api.nvim_win_get_buf          = _rvim_api_win_get_buf
          vim.api.nvim_win_set_buf          = _rvim_api_win_set_buf
          vim.api.nvim_win_get_position     = _rvim_api_win_get_position
          vim.api.nvim_win_get_tabpage      = _rvim_api_win_get_tabpage
          vim.api.nvim_win_get_number       = _rvim_api_win_get_number
          vim.api.nvim_win_call             = _rvim_api_win_call
          vim.api.nvim_get_current_win      = _rvim_api_get_current_win
          vim.api.nvim_set_current_win      = _rvim_api_set_current_win
          vim.api.nvim_get_current_tabpage  = _rvim_api_get_current_tabpage
          vim.api.nvim_list_tabpages        = _rvim_api_list_tabpages
          vim.api.nvim_tabpage_list_wins    = _rvim_api_tabpage_list_wins
          vim.api.nvim_tabpage_get_number   = _rvim_api_tabpage_get_number
          vim.api.nvim_tabpage_is_valid     = _rvim_api_tabpage_is_valid

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
          -- Legacy per-scope option setters (deprecated in 0.7+ but
          -- plenary/telescope still use them).
          vim.api.nvim_win_get_option       = function(_w, n) return _rvim_api_get_option(n) end
          vim.api.nvim_win_set_option       = function(w, n, v)
            if n == "winhl" then _rvim_api_win_set_winhl(w, v) else _rvim_api_set_option(n, v) end
          end
          vim.api.nvim_get_mode             = _rvim_api_get_mode
          vim.api.nvim_command              = _rvim_api_command
          vim.api.nvim_call_function        = _rvim_api_call_function
          vim.api.nvim_echo                 = _rvim_api_echo
          vim.api.nvim_err_writeln          = _rvim_api_err_writeln
          vim.api.nvim_out_write            = _rvim_api_out_write
          vim.api.nvim_strwidth             = _rvim_api_strwidth
          vim.api.nvim_replace_termcodes    = _rvim_api_replace_termcodes
          vim.api.nvim_set_hl               = _rvim_api_set_hl
          vim.api.nvim_get_hl               = _rvim_api_get_hl
          vim.api.nvim_get_hl_by_name       = function(name, _rgb) return _rvim_api_get_hl(0, { name = name }) end
          vim.api.nvim_get_hl_id_by_name    = function(name) return _rvim_api_get_hl_id(name) end

          -- Floating windows + scratch buffers.
          vim.api.nvim_create_buf           = _rvim_api_create_buf
          vim.api.nvim_open_win             = _rvim_api_open_win
          vim.api.nvim_win_close            = _rvim_api_win_close
          vim.api.nvim_win_get_config       = _rvim_api_win_get_config
          vim.api.nvim_win_set_config       = _rvim_api_win_set_config

          -- Buffer-local keymaps.
          vim.api.nvim_buf_set_keymap       = _rvim_api_buf_set_keymap
          vim.api.nvim_buf_del_keymap       = _rvim_api_buf_del_keymap

          -- Extmarks + namespaces.
          vim.api.nvim_create_namespace     = _rvim_api_create_namespace
          vim.api.nvim_buf_set_extmark      = _rvim_api_buf_set_extmark
          vim.api.nvim_buf_get_extmarks     = _rvim_api_buf_get_extmarks
          vim.api.nvim_buf_del_extmark      = _rvim_api_buf_del_extmark
          vim.api.nvim_buf_clear_namespace  = _rvim_api_buf_clear_namespace
          vim.api.nvim_buf_add_highlight    = _rvim_api_buf_add_highlight

          -- Buffer change listeners + key synthesis.
          vim.api.nvim_buf_attach           = _rvim_api_buf_attach
          vim.api.nvim_feedkeys             = _rvim_api_feedkeys

          -- User-defined ex commands (lazy.nvim's :Lazy, plugin :Foo).
          vim.api.nvim_create_user_command  = _rvim_api_create_user_command
          vim.api.nvim_del_user_command     = _rvim_api_del_user_command

          -- Keymap introspection.
          vim.api.nvim_get_keymap           = _rvim_api_get_keymap
          vim.api.nvim_buf_get_keymap       = _rvim_api_buf_get_keymap

          -- Runtimepath, exec, autocmd dispatch, global keymap.
          vim.api.nvim_get_runtime_file     = _rvim_api_get_runtime_file
          vim.api.nvim_list_runtime_paths   = _rvim_api_list_runtime_paths
          vim.api.nvim_list_uis             = _rvim_api_list_uis
          vim.api.nvim_set_keymap           = _rvim_api_set_keymap
          vim.api.nvim_del_keymap           = _rvim_api_del_keymap
          vim.api.nvim_exec                 = _rvim_api_exec
          vim.api.nvim_exec2                = _rvim_api_exec2
          vim.api.nvim_exec_autocmds        = _rvim_api_exec_autocmds
          vim.api.nvim_clear_autocmds       = _rvim_api_clear_autocmds
          vim.api.nvim_get_autocmds         = _rvim_api_get_autocmds
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
          elsif opts_h['win'] && name.to_s == 'winhl'
            win = Rvim::Lua::Api.resolve_window(editor, opts_h['win'])
            win.winhl = coerced.to_s if win
          else
            editor.settings.set(name.to_s, coerced)
          end
        end

        # nvim_win_set_option(win, 'winhl', value) — record the win-local
        # highlight remap on the Window so the renderer can resolve
        # Normal -> TelescopeBorder / etc when painting that float.
        state.function '_rvim_api_win_set_winhl' do |winid, value|
          win = Rvim::Lua::Api.resolve_window(editor, winid)
          win.winhl = value.to_s if win
        end

        state.function '_rvim_api_get_mode' do
          { 'mode' => Rvim::Lua::Fn.mode(editor), 'blocking' => false }
        end

        state.function '_rvim_api_command' do |cmd|
          parsed = Rvim::Command.parse(cmd.to_s)
          Rvim::Command.execute(editor, parsed) if parsed
        end

        # nvim_call_function(name, args) — invoke a vim function by
        # name. Equivalent to vim.fn[name](unpack(args)). Plenary's
        # log module and many telescope helpers use this rather than
        # the dotted vim.fn.foo form.
        state.function '_rvim_api_call_function' do |fname, fargs|
          fn = state.eval("return vim.fn[#{fname.to_s.inspect}]")
          next nil if fn.nil?

          args = if fargs.respond_to?(:to_h)
                   h = fargs.to_h
                   (1..h.size).map { |i| h[i] || h[i.to_f] }
                 elsif fargs.is_a?(Array)
                   fargs
                 else
                   []
                 end
          fn.call(*args)
        end

        state.function('_rvim_api_echo') { |_chunks, history, _opts| editor.status_message = '' if history }
        state.function('_rvim_api_err_writeln') { |msg| editor.status_message = "ERR: #{msg}" }
        state.function('_rvim_api_out_write') { |msg| editor.status_message = msg.to_s }

        state.function('_rvim_api_strwidth') { |s| s.to_s.length }

        state.function '_rvim_api_replace_termcodes' do |s, _from_part, _do_lt, _special|
          Rvim::Keymap.expand(s.to_s, leader: editor.mapleader)
        end

        # The functional _rvim_api_set_hl lives in install_extmark_api
        # below; without that real impl, plugin colors silently no-op'd.

        install_float_api(state, editor)
        install_keymap_api(state, editor)
        install_extmark_api(state, editor)
        install_attach_feedkeys_api(state, editor)
      end

      # nvim_get_keymap(mode) / nvim_buf_get_keymap(buf, mode) —
      # enumerate registered mappings. Each entry mirrors NeoVim's
      # shape so plugins like which-key.nvim can introspect.
      def self.install_keymap_introspection_api(state, editor)
        state.function '_rvim_api_get_keymap' do |mode_arg|
          mode = lua_mode_to_internal(mode_arg.to_s)
          serialize_keymap_entries(editor.keymap, mode, buffer: 0)
        end

        state.function '_rvim_api_buf_get_keymap' do |bufnr, mode_arg|
          buf = resolve_buffer(editor, bufnr) || editor.current_buffer
          mode = lua_mode_to_internal(mode_arg.to_s)
          buf && buf.keymap? ? serialize_keymap_entries(buf.keymap, mode, buffer: buf.id) : []
        end
      end

      def self.lua_mode_to_internal(mode)
        case mode
        when 'n' then :normal
        when 'i' then :insert
        when 'v', 'x' then :visual
        when 'o' then :op_pending
        when 'c' then :cmdline
        when '' then :normal
        else :normal
        end
      end

      def self.serialize_keymap_entries(keymap, mode, buffer:)
        out = []
        keymap.each(mode) do |lhs, mapping|
          out << {
            'lhs'      => lhs.to_s,
            'lhsraw'   => lhs.to_s,
            'rhs'      => mapping.rhs.to_s,
            'mode'     => internal_mode_to_lua(mode),
            'noremap'  => mapping.recursive ? 0 : 1,
            'silent'   => mapping.silent ? 1 : 0,
            'nowait'   => 0,
            'expr'     => 0,
            'script'   => 0,
            'buffer'   => buffer,
            # callback presence is what plugins check most often.
            'callback' => mapping.callback ? true : nil,
            'desc'     => '',
          }
        end
        out
      end

      def self.internal_mode_to_lua(mode)
        case mode
        when :normal then 'n'
        when :insert then 'i'
        when :visual then 'v'
        when :op_pending then 'o'
        when :cmdline then 'c'
        else 'n'
        end
      end

      # nvim_create_user_command(name, command, opts):
      #   - name: PascalCase command name (e.g. "Lazy")
      #   - command: string body OR a Lua function (callback) receiving
      #     an opts table with args/fargs/bang/name/etc.
      #   - opts: { nargs = "?"/"*"/"+"/0/1, bang = bool, range = bool,
      #     desc = string } — only nargs/bang are enforced here; the
      #     rest are accepted-and-ignored for plugin compatibility.
      def self.install_user_command_api(state, editor)
        state.function '_rvim_api_create_user_command' do |name, command, opts|
          n = name.to_s
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          nargs = opts_h['nargs']
          nargs_str = case nargs
                      when nil then '0'
                      when Numeric then nargs.to_i.to_s
                      else nargs.to_s
                      end

          callback = nil
          body = ''
          if command.is_a?(Rufus::Lua::Function)
            cb_lua = command
            callback = lambda do |o|
              cb_lua.call(o)
            rescue StandardError, ScriptError => e
              editor.status_message = "E:#{n}: #{e.message}"
            end
          else
            body = command.to_s
          end

          editor.user_commands[n] = Rvim::Command::UserCommand.new(
            name: n,
            nargs: nargs_str,
            body: body,
            callback: callback,
            bang_allowed: opts_h['bang'] == true,
            range_allowed: opts_h['range'] == true,
          )
          nil  # don't leak the UserCommand struct back to Lua
        end

        state.function '_rvim_api_del_user_command' do |name|
          editor.user_commands.delete(name.to_s)
          nil
        end
      end

      # nvim_get_runtime_file(name, all) — walk &runtimepath looking
      # for `name` (a relative path or simple glob like
      # "colors/*.lua"). Returns the first match, or all matches when
      # `all` is true. lazy.nvim uses this to discover plugin
      # entrypoints and colorschemes.
      #
      # nvim_list_runtime_paths — sibling that just returns the
      # expanded runtimepath array; cheap and lazy.nvim calls it on
      # every startup to seed its package index.
      def self.install_runtime_api(state, editor)
        state.function '_rvim_api_list_runtime_paths' do
          runtime_paths(editor)
        end

        state.function '_rvim_api_list_uis' do
          # Plugins use #vim.api.nvim_list_uis() == 0 to detect
          # headless / batch mode. We're a TTY UI, so return one.
          rows, cols = begin
            Reline::IOGate.get_screen_size
          rescue StandardError
            [24, 80]
          end
          [{ 'width' => cols, 'height' => rows, 'rgb' => true,
             'chan' => 1, 'ext_cmdline' => false, 'ext_popupmenu' => false,
             'ext_tabline' => false, 'ext_wildmenu' => false }]
        end

        state.function '_rvim_api_get_runtime_file' do |name, all|
          glob_runtime(editor, name.to_s, all == true)
        end
      end

      def self.runtime_paths(editor)
        editor.settings.get(:runtimepath).to_s.split(',').filter_map do |p|
          stripped = p.strip
          stripped.empty? ? nil : File.expand_path(stripped)
        end
      end

      def self.glob_runtime(editor, name, all)
        results = []
        runtime_paths(editor).each do |dir|
          # Dir.glob already handles `*` / `?` / `**`; bare names
          # match a single literal file path.
          Dir.glob(File.join(dir, name)).each do |match|
            results << match
            return results unless all
          end
        end
        results
      end

      # nvim_set_keymap(mode, lhs, rhs, opts) — global counterpart of
      # nvim_buf_set_keymap. lazy.nvim's lazy-loading shims use this
      # to install <Plug> mappings before the real plugin loads.
      def self.install_global_keymap_api(state, editor)
        state.function '_rvim_api_set_keymap' do |mode_arg, lhs, rhs, opts|
          modes = Rvim::Lua::Keymap.resolve_modes(mode_arg)
          expanded_lhs = Rvim::Keymap.expand(lhs.to_s, leader: editor.mapleader)
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          recursive = opts_h['noremap'] != true
          silent    = opts_h['silent'] == true
          callback  = opts_h['callback']
          if callback.is_a?(Rufus::Lua::Function)
            cb = -> { callback.call }
            editor.keymap.add(modes, expanded_lhs, '', recursive: recursive, silent: silent, callback: cb)
          else
            expanded_rhs = Rvim::Keymap.expand(rhs.to_s, leader: editor.mapleader)
            editor.keymap.add(modes, expanded_lhs, expanded_rhs, recursive: recursive, silent: silent)
          end
        end

        state.function '_rvim_api_del_keymap' do |mode_arg, lhs|
          modes = Rvim::Lua::Keymap.resolve_modes(mode_arg)
          expanded_lhs = Rvim::Keymap.expand(lhs.to_s, leader: editor.mapleader)
          editor.keymap.remove(modes, expanded_lhs)
        end
      end

      # nvim_exec(src, output) -> string
      # nvim_exec2(src, opts)  -> { output = string? }
      #
      # Multiline vimscript-ish blocks. We split on \n and run each
      # non-empty line through Rvim::Command. When output capture is
      # requested we swap in a temporary sink so :echo / :messages /
      # status writes are collected. (Real NeoVim captures everything
      # the command writes to the message stream; we approximate by
      # capturing status_message writes, which already cover most
      # plugin probes like `vim.api.nvim_exec("set runtimepath?",
      # true)`.)
      def self.install_exec_api(state, editor)
        state.function '_rvim_api_exec' do |src, output|
          exec_multiline(editor, src.to_s, capture: output == true)
        end

        state.function '_rvim_api_exec2' do |src, opts|
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          captured = exec_multiline(editor, src.to_s, capture: opts_h['output'] == true)
          { 'output' => captured }
        end
      end

      class CaptureSink
        def initialize
          @buf = +''
        end

        def <<(msg)
          @buf << msg.to_s << "\n"
        end

        def close; end

        attr_reader :buf
      end

      def self.exec_multiline(editor, src, capture:)
        sink = capture ? CaptureSink.new : nil
        prev_sink = editor.instance_variable_get(:@redir_sink)
        editor.instance_variable_set(:@redir_sink, sink) if sink

        begin
          src.each_line do |line|
            line = line.chomp.strip
            next if line.empty? || line.start_with?('"')

            parsed = Rvim::Command.parse(line)
            Rvim::Command.execute(editor, parsed) if parsed
          end
        ensure
          editor.instance_variable_set(:@redir_sink, prev_sink) if sink
        end

        sink ? sink.buf : ''
      end

      # nvim_exec_autocmds(event, opts) — fire an event by name.
      # opts.pattern (string|array) and opts.data (anything) shape the
      # value passed to listeners. lazy.nvim emits its own User events
      # ("LazyLoad", "VeryLazy", "LazyDone") through this; nothing
      # would fire those without it.
      def self.normalize_event_filter(raw)
        return nil if raw.nil? || raw == ''

        arr = if raw.respond_to?(:to_h)
                raw.to_h.values
              elsif raw.is_a?(Array)
                raw
              else
                [raw]
              end
        # Autocommands store events as lowercase symbols; the filter
        # gets case-insensitive matching to mirror NeoVim.
        arr.map { |e| e.to_s.downcase }
      end

      def self.install_exec_autocmds_api(state, editor)
        # nvim_get_autocmds(opts) — list registered autocmds, filtered
        # by opts.event (string|array) and opts.pattern. Returns each
        # entry as a hash matching NeoVim's shape: { id, event,
        # pattern, command, callback, group, ... }. Used by plugins
        # to detect/clean up old registrations before installing new
        # ones (lazy.nvim's event handler does this).
        state.function '_rvim_api_get_autocmds' do |opts|
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          ev_filter = normalize_event_filter(opts_h['event'])

          out = []
          editor.autocommands.each do |entry|
            next if ev_filter && !ev_filter.include?(entry.event.to_s.downcase)

            out << {
              'id'       => entry.object_id,
              'event'    => entry.event.to_s,
              'pattern'  => entry.pattern.to_s,
              'command'  => entry.command.to_s,
              'callback' => nil, # we don't surface Ruby lambdas
              'group'    => entry.group,
              'group_name' => entry.group ? entry.group.to_s : nil,
              'buflocal' => false,
              'once'     => false,
              'desc'     => '',
            }
          end
          out
        end

        state.function '_rvim_api_exec_autocmds' do |events, opts|
          events_arr = if events.respond_to?(:to_h)
                         events.to_h.values.map(&:to_s)
                       else
                         [events.to_s]
                       end
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          patterns = case (raw = opts_h['pattern'])
                     when nil, '' then [nil]
                     when Array then raw.map(&:to_s)
                     else
                       if raw.respond_to?(:to_h)
                         raw.to_h.values.map(&:to_s)
                       else
                         [raw.to_s]
                       end
                     end

          events_arr.each do |ev|
            patterns.each do |pat|
              # Autocommands#fire matches by glob; pass the pattern
              # itself as the "value" for User events so a listener
              # with pattern: "Lazy*" fires for "LazyLoad" et al.
              value = pat || ev
              editor.autocommands.fire(ev, value, editor)
            end
          end
        end

        # nvim_clear_autocmds(opts) — remove registered autocmds
        # matching opts (event/group/pattern/buffer). Telescope's
        # close path calls it to remove the BufLeave autocmd on the
        # prompt buffer so close_windows doesn't fire twice.
        state.function '_rvim_api_clear_autocmds' do |opts|
          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          ev_filter = normalize_event_filter(opts_h['event'])
          grp = opts_h['group']
          # group can be passed as either an integer id (from
          # nvim_create_augroup) or a string name.
          ents = editor.autocommands.instance_variable_get(:@entries)
          ents.reject! do |entry|
            keep = true
            if ev_filter && !ev_filter.empty?
              keep = false unless ev_filter.include?(entry.event.to_s.downcase)
            end
            if keep && grp
              keep = false unless entry.group == grp || entry.group.to_s == grp.to_s
            end
            !keep
          end
        end
      end

      def self.install_attach_feedkeys_api(state, editor)
        # nvim_buf_attach(bufnr, send_buffer, opts) -> bool
        # opts.on_lines = function(event, bufnr, tick, first, last, new_last, byte_count)
        state.function '_rvim_api_buf_attach' do |bufnr, _send_buffer, opts|
          buf = resolve_buffer(editor, bufnr)
          next false unless buf

          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          on_lines = opts_h['on_lines']
          if on_lines.is_a?(Rufus::Lua::Function)
            cb = ->(*args) { on_lines.call(*args) }
            buf.attach_listener(cb)
            true
          else
            false
          end
        end

        # nvim_feedkeys(keys, mode, escape_ks)
        # mode is a string of flags; 'n' = no remap, 'i' = insert,
        # 'm' = remap (we just always remap, vim's default), 't' = typed.
        # escape_ks is irrelevant (no K_SPECIAL on rvim).
        state.function '_rvim_api_feedkeys' do |keys, _mode, _escape_ks|
          str = keys.to_s
          # Walk byte-by-byte so multi-byte UTF-8 keys are preserved
          # as their constituent bytes (matches what Reline delivers
          # for real typed input).
          str.each_char do |ch|
            editor.update(Reline::Key.new(ch, nil, false))
          end
        end
      end

      def self.install_extmark_api(state, editor)
        state.function('_rvim_api_create_namespace') { |name| editor.create_namespace(name.to_s) }

        # nvim_get_hl(ns_id, opts) — return the highlight group definition
        # for opts.name / opts.id. NeoVim hands back { fg, bg, bold, ... }
        # (or { link = "..." } for unresolved links). We only keep the
        # rendered SGR pairs on disk, not the original spec, so the
        # honest return is an empty table — callers that probe e.g.
        # `result.bg` see nil and skip behaviors that depend on the
        # palette. lazy.nvim uses this to decide whether to draw a
        # backdrop; the empty-table path matches "no palette known".
        state.function('_rvim_api_get_hl') { |_ns_id, _opts| {} }
        # nvim_get_hl_id_by_name — returns the integer id of a hl group.
        # We don't track stable ids; hash-of-name is good enough so
        # callers that want "some non-zero integer" get one.
        state.function('_rvim_api_get_hl_id') { |name| name.to_s.hash.abs }

        # nvim_set_hl(ns_id, name, val) — ns_id is ignored for now
        # (one global registry). val is a table of fg/bg/bold/etc.
        state.function '_rvim_api_set_hl' do |_ns_id, name, val|
          spec = val.respond_to?(:to_h) ? val.to_h : {}
          editor.hl_groups.define(name.to_s, spec)
        end

        # nvim_buf_set_extmark(bufnr, ns_id, line, col, opts) -> id
        state.function '_rvim_api_buf_set_extmark' do |bufnr, ns_id, line, col, opts|
          buf = resolve_buffer(editor, bufnr)
          next 0 unless buf

          opts_h = opts.respond_to?(:to_h) ? opts.to_h : {}
          # If the caller passed an explicit id (re-positioning an
          # existing mark), reuse it; else allocate a fresh id.
          mark_id = opts_h['id']&.to_i
          mark_id = buf.next_extmark_id! if mark_id.nil? || mark_id <= 0
          buf.extmarks[ns_id.to_i][mark_id] = {
            line: line.to_i,
            col: col.to_i,
            end_row: opts_h['end_row']&.to_i,
            end_col: opts_h['end_col']&.to_i,
            hl_group: opts_h['hl_group']&.to_s,
            priority: (opts_h['priority'] || 100).to_i,
          }
          mark_id
        end

        # nvim_buf_get_extmarks(bufnr, ns_id, start, end_, opts) -> [[id, line, col], ...]
        state.function '_rvim_api_buf_get_extmarks' do |bufnr, ns_id, _start, _end_, _opts|
          buf = resolve_buffer(editor, bufnr)
          next [] unless buf

          (buf.extmarks[ns_id.to_i] || {}).map { |mid, m| [mid, m[:line], m[:col]] }
        end

        # nvim_buf_del_extmark(bufnr, ns_id, id) -> bool
        state.function '_rvim_api_buf_del_extmark' do |bufnr, ns_id, id|
          buf = resolve_buffer(editor, bufnr)
          next false unless buf

          !(buf.extmarks[ns_id.to_i] || {}).delete(id.to_i).nil?
        end

        # nvim_buf_clear_namespace(bufnr, ns_id, start, end_)
        state.function '_rvim_api_buf_clear_namespace' do |bufnr, ns_id, line_start, line_end|
          buf = resolve_buffer(editor, bufnr)
          next unless buf

          ns = ns_id.to_i
          ls = line_start.to_i
          le = line_end.to_i
          marks = buf.extmarks[ns] || {}
          if ls <= 0 && le == -1
            marks.clear
          else
            marks.delete_if { |_, m| (m[:line] || 0).between?(ls, le == -1 ? (1 << 30) : le) }
          end
        end

        # nvim_buf_add_highlight(bufnr, ns_id, hl_group, line, col_start, col_end) -> int
        # Sugar over set_extmark — the legacy NeoVim signature most
        # older plugins still call.
        state.function '_rvim_api_buf_add_highlight' do |bufnr, ns_id, hl_group, line, col_start, col_end|
          buf = resolve_buffer(editor, bufnr)
          next 0 unless buf

          ns = ns_id.to_i
          ns = editor.create_namespace('') if ns.zero?
          mark_id = buf.next_extmark_id!
          line_text = buf.lines[line.to_i] || ''
          ec = col_end.to_i
          ec = line_text.bytesize if ec < 0
          buf.extmarks[ns][mark_id] = {
            line: line.to_i,
            col: col_start.to_i,
            end_row: line.to_i,
            end_col: ec,
            hl_group: hl_group.to_s,
            priority: 100,
          }
          mark_id
        end
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

        state.function '_rvim_api_win_get_cursor' do |winid|
          # NeoVim returns {row(1-based), col(0-based)} for the
          # *target* window's buffer. Telescope reads the results
          # window's cursor right after set_cursor moves it to the
          # bottom (for descending sort); falling back to the
          # editor's globals here would read the prompt buffer's
          # cursor instead, and telescope's selection logic would
          # think the row never moved.
          win = Rvim::Lua::Api.resolve_window(editor, winid)
          if win && win.buffer && !editor.current_window.equal?(win)
            buf = win.buffer
            [(buf.line_index || 0) + 1, buf.byte_pointer || 0]
          else
            [editor.line_index + 1, editor.byte_pointer]
          end
        end

        state.function '_rvim_api_win_set_cursor' do |winid, pos|
          arr = if pos.respond_to?(:to_h)
                  pos.to_h.values
                elsif pos.is_a?(Array)
                  pos
                else
                  []
                end
          row = arr[0].to_i - 1
          col = arr[1].to_i
          win = Rvim::Lua::Api.resolve_window(editor, winid)
          # The cursor lives on the target window's buffer, not the
          # editor's globals. Telescope sets the cursor on its prompt
          # window during setup; if we wrote that to the editor's
          # @byte_pointer we'd clobber the cursor of the still-current
          # buffer (e.g. [No Name]) and a later `i` + char would index
          # past the line's end, crashing Reline's byteinsert.
          if win && win.buffer
            buf = win.buffer
            target = buf.lines[[row, 0].max] || ''
            buf.line_index = [[row, 0].max, [(buf.lines.size - 1), 0].max].min
            buf.byte_pointer = [col, 0].max.clamp(0, target.bytesize)
            if editor.current_window.equal?(win)
              editor.instance_variable_set(:@line_index, buf.line_index)
              editor.instance_variable_set(:@byte_pointer, buf.byte_pointer)
            end
            # Scroll the window so the requested row is visible.
            # Telescope's descending-sort path positions the cursor at
            # max_results to make the buffer's last 14 rows show in a
            # 14-tall results float — but only the cursor move alone
            # doesn't drive the viewport on rvim's floats. Mirror
            # NeoVim's "scrolloff = 0" behaviour: keep the row within
            # the visible window, scrolling scroll_top forward when
            # the cursor would otherwise be below the bottom edge.
            height = win.height.to_i
            if height.positive?
              row_idx = buf.line_index
              st = win.scroll_top.to_i
              if row_idx < st
                win.scroll_top = row_idx
              elsif row_idx >= st + height
                win.scroll_top = row_idx - height + 1
              end
            end
          end
        end

        state.function('_rvim_api_win_get_height') { |winid| (resolve.call(winid)&.height) || 24 }
        state.function('_rvim_api_win_set_height') { |winid, h| w = resolve.call(winid); w.height = h.to_i if w }
        state.function('_rvim_api_win_get_width')  { |winid| (resolve.call(winid)&.width) || 80 }
        state.function('_rvim_api_win_set_width')  { |winid, w_| w = resolve.call(winid); w.width = w_.to_i if w }
        state.function('_rvim_api_win_get_buf')    { |winid| resolve.call(winid)&.buffer&.id || 0 }
        state.function('_rvim_api_win_set_buf') do |winid, bufnr|
          w = resolve.call(winid)
          buf = resolve_buffer(editor, bufnr)
          w.buffer = buf if w && buf
        end
        state.function('_rvim_api_win_get_position') do |winid|
          w = resolve.call(winid)
          # NeoVim returns {row, col}. Tiled wins live at the screen
          # origin in our model; floats carry their own row/col.
          if w && w.floating?
            [w.row || 0, w.col || 0]
          else
            [0, 0]
          end
        end
        state.function('_rvim_api_win_get_tabpage') { |_winid| 1 }
        state.function('_rvim_api_win_get_number')  { |winid|
          all = (editor.windows || []) + (editor.respond_to?(:floating_windows) ? editor.floating_windows : [])
          idx = all.index { |w| w.id == winid.to_i }
          (idx || 0) + 1
        }
        state.function('_rvim_api_win_call') do |winid, fn|
          # Temporarily make `winid` current, run fn, restore. Plugins
          # use this to set options in the context of a specific window.
          prev = editor.current_window
          win = resolve.call(winid)
          editor.instance_variable_set(:@current_window, win) if win
          begin
            fn.call if fn.respond_to?(:call)
          ensure
            editor.instance_variable_set(:@current_window, prev)
          end
        end
        state.function('_rvim_api_get_current_win') { editor.current_window&.id || 0 }
        state.function('_rvim_api_set_current_win') do |winid|
          win = resolve_window(editor, winid)
          # Focus changes mean the buffer context changes too —
          # telescope calls this to land the user in its prompt
          # window so typing goes into the prompt buffer (and the
          # on_lines listener triggers refiltering). Without
          # swapping the buffer, typing keeps editing the previous
          # buffer and no on_lines fires on the prompt.
          editor.send(:enter_window, win) if win
        end

        # Tab page API — rvim doesn't have full tab semantics; surface
        # a single fake "tab 1" so plugins that probe survive.
        state.function('_rvim_api_get_current_tabpage') { 1 }
        state.function('_rvim_api_list_tabpages') { [1] }
        state.function('_rvim_api_tabpage_list_wins') do |_tabid|
          all = (editor.windows || []) + (editor.respond_to?(:floating_windows) ? editor.floating_windows : [])
          all.map(&:id)
        end
        state.function('_rvim_api_tabpage_get_number') { |_tabid| 1 }
        state.function('_rvim_api_tabpage_is_valid')   { |tabid| tabid.to_i == 1 }
      end

      def self.resolve_window(editor, winid)
        n = winid.to_i
        return editor.current_window if n.zero?

        # Each Window now carries a stable id (Window#id) so floats
        # and tiled windows live in the same namespace. Return nil
        # rather than falling back to current_window when the winid
        # is unknown — telescope's close path calls utils.win_delete
        # on already-closed window ids, and the fallback caused
        # nvim_win_get_buf to point at the [No Name] buffer, which
        # then got buf_delete'd in the cascade.
        all = (editor.windows || []) + (editor.respond_to?(:floating_windows) ? editor.floating_windows : [])
        all.find { |w| w.id == n }
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
          # Strings coming back from rufus arrive tagged ASCII-8BIT
          # even when their bytes are valid UTF-8 (e.g. telescope's
          # box-drawing borders). Re-tag as UTF-8 so Reline's width
          # calculator, the renderer, and downstream consumers don't
          # explode on the first multibyte char.
          coerce = ->(v) { String.new(v.to_s, encoding: editor.encoding) }
          new_lines = if replacement.respond_to?(:to_h)
                        replacement.to_h.values.map(&coerce)
                      elsif replacement.is_a?(Array)
                        replacement.map(&coerce)
                      else
                        []
                      end
          buf.lines = lines[0...s] + new_lines + (lines[e..] || [])
          if buf == editor.current_buffer
            editor.instance_variable_set(:@buffer_of_lines, buf.lines)
            editor.instance_variable_set(:@modified, true)
          end
        end

        # nvim_buf_set_text(buf, srow, scol, erow, ecol, replacement) —
        # replace a byte-range that may span multiple rows with the
        # given lines. telescope uses it to update result rows in-place
        # without disturbing surrounding highlights.
        state.function '_rvim_api_buf_set_text' do |bufnr, srow, scol, erow, ecol, replacement|
          buf = resolve.call(bufnr)
          next nil unless buf

          lines = buf.lines || []
          sr = srow.to_i
          sc = scol.to_i
          er = erow.to_i
          ec = ecol.to_i
          coerce = ->(v) { String.new(v.to_s, encoding: editor.encoding) }
          repl_lines = if replacement.respond_to?(:to_h)
                         replacement.to_h.values.map(&coerce)
                       elsif replacement.is_a?(Array)
                         replacement.map(&coerce)
                       else
                         ['']
                       end
          repl_lines = [''] if repl_lines.empty?

          prefix = if sr < lines.size
                     (lines[sr] || '').byteslice(0, sc).to_s
                   else
                     ''
                   end
          suffix = if er < lines.size
                     line = lines[er] || ''
                     line.byteslice(ec, line.bytesize - ec).to_s
                   else
                     ''
                   end

          spliced = repl_lines.dup
          spliced[0] = prefix + (spliced[0] || '')
          spliced[-1] = (spliced[-1] || '') + suffix
          spliced.map! { |l| String.new(l, encoding: editor.encoding) }

          buf.lines = (lines[0...sr] || []) + spliced + (lines[(er + 1)..] || [])
          if buf == editor.current_buffer
            editor.instance_variable_set(:@buffer_of_lines, buf.lines)
            editor.instance_variable_set(:@modified, true)
          end
        end

        # nvim_buf_delete(bufnr, opts) — telescope's close action
        # calls this to tear down its scratch prompt/results/preview
        # buffers when the picker exits. opts (force/unload) is
        # ignored: rvim doesn't distinguish between unload + delete
        # for scratch buffers, and the action just wants the buffer
        # gone from the list.
        state.function '_rvim_api_buf_delete' do |bufnr, _opts|
          buf = resolve.call(bufnr)
          next nil unless buf

          # If the buffer is current, fall back to another live one
          # so swap_to_buffer below has somewhere to go.
          if editor.current_buffer&.equal?(buf)
            other = editor.buffers.values.find { |b| !b.equal?(buf) }
            editor.swap_to_buffer(other) if other
          end
          editor.buffers.delete(buf.id)
          (editor.instance_variable_get(:@buffer_order) || []).delete(buf.id)
          # Drop any floats backed by this buffer so the renderer
          # doesn't try to draw a buffer that's been deleted.
          if editor.respond_to?(:floating_windows)
            editor.floating_windows.dup.each do |w|
              editor.close_floating_window(w) if w.buffer.equal?(buf)
            end
          end
          nil
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

        # nvim_buf_call(buf, fn) — run fn with `buf` temporarily as the
        # current buffer, then restore the original. Telescope's buffer
        # previewer uses this to drive `:norm gg / search / zz` against
        # the preview buffer without disturbing the user's window.
        # We don't model NeoVim's "execute in another buffer's context"
        # primitive; we approximate by swapping current_buffer for the
        # duration of the call.
        state.function '_rvim_api_buf_call' do |bufnr, fn|
          buf = resolve.call(bufnr)
          if buf && fn.is_a?(Rufus::Lua::Function)
            saved = editor.current_buffer
            begin
              editor.swap_to_buffer(buf) if buf != saved
              fn.call
            ensure
              editor.swap_to_buffer(saved) if saved && buf != saved
            end
          end
          nil
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
