# frozen_string_literal: true

module Rvim
  module Lua
    # vim.keymap.set(mode, lhs, rhs, opts)
    # vim.keymap.del(mode, lhs)
    #
    # mode: 'n'/'i'/'v'/'x'/'o'/'c'/'' (or array)
    # rhs: string ex command, or function (Lua callback held in registry)
    # opts: { silent = bool, noremap = bool, ... }
    module Keymap
      module_function

      MODE_MAP = {
        'n' => :normal, 'i' => :insert,
        'v' => :visual, 'x' => :visual,
        'o' => :op_pending, 'c' => :cmdline,
        '' => %i[normal visual op_pending],
      }.freeze

      def install(state, editor, runtime)
        state.function '_rvim_keymap_set' do |mode_arg, lhs, rhs, opts|
          modes = resolve_modes(mode_arg)
          opts_h = case opts
                   when Hash then opts
                   when nil then {}
                   else (opts.respond_to?(:to_h) ? opts.to_h : {})
                   end
          silent = opts_h['silent'] == true
          # Match NeoVim's vim.keymap.set default: non-recursive unless
          # the caller explicitly opts into recursion with `remap = true`
          # (or `noremap = false`). Without this, `map.set('v', '>', '>gv')`
          # recurses on the inner '>' and blows the stack.
          recursive = opts_h['noremap'] == false || opts_h['remap'] == true
          expanded_lhs = Rvim::Keymap.expand(lhs.to_s, leader: editor.mapleader)

          # opts.buffer routes to a buffer-local keymap. `0` means
          # current buffer; a positive integer is a specific bufnr.
          target_keymap = keymap_for(editor, opts_h['buffer'])

          if rhs.is_a?(Rufus::Lua::Function)
            cb_lua = rhs
            # Plugin-side errors in a mapping callback (e.g. telescope's
            # actions.close indexing a stale picker after the buffer is
            # gone) shouldn't crash the editor — surface as a status
            # message instead.
            cb = lambda do
              cb_lua.call
            rescue Rufus::Lua::LuaError => e
              msg = e.message.to_s
              short = msg[/[^\/]+\.lua:\d+:[^']+/].to_s
              editor.status_message = "E5108: keymap callback: #{short.empty? ? msg[0, 120] : short}"
              nil
            end
            target_keymap.add(modes, expanded_lhs, '', recursive: recursive, silent: silent, callback: cb)
          elsif (cmd_match = rhs.to_s.match(/\A<[Cc][Mm][Dd]>(.*?)<[Cc][Rr]>\z/m))
            # `<cmd>foo<CR>` runs `foo` as an ex command WITHOUT
            # leaving the current mode (no `:` framing, no mode flip).
            # Many plugins lean on this for in-mode actions; expanding
            # it as plain bytes would just type "<cmd>foo<CR>" into the
            # buffer.
            ex_cmd = cmd_match[1].to_s
            cb = lambda do
              parsed = Rvim::Command.parse(ex_cmd)
              Rvim::Command.execute(editor, parsed) if parsed
            rescue StandardError => e
              editor.status_message = "E5108: keymap <cmd>: #{e.message[0, 120]}"
            end
            target_keymap.add(modes, expanded_lhs, '', recursive: recursive, silent: silent, callback: cb)
          else
            expanded_rhs = Rvim::Keymap.expand(rhs.to_s, leader: editor.mapleader)
            target_keymap.add(modes, expanded_lhs, expanded_rhs, recursive: recursive, silent: silent)
          end
        end

        state.function '_rvim_keymap_del' do |mode_arg, lhs|
          modes = resolve_modes(mode_arg)
          expanded_lhs = Rvim::Keymap.expand(lhs.to_s, leader: editor.mapleader)
          editor.keymap.remove(modes, expanded_lhs)
        end

        state.eval(<<~LUA)
          vim.keymap = {
            set = function(mode, lhs, rhs, opts) _rvim_keymap_set(mode, lhs, rhs, opts) end,
            del = function(mode, lhs) _rvim_keymap_del(mode, lhs) end,
          }
        LUA
      end

      # Resolve where a keymap entry should land based on `opts.buffer`.
      # nil  → global editor.keymap.
      # 0    → current buffer's local keymap.
      # int  → buffer with that id's local keymap (falls back to global
      #        when no buffer matches, mirroring NeoVim's "silent ignore").
      def keymap_for(editor, buffer_opt)
        return editor.keymap if buffer_opt.nil? || buffer_opt == false

        bufnr = case buffer_opt
                when true then 0
                else buffer_opt.to_i
                end
        target = if bufnr.zero?
                   editor.current_buffer
                 else
                   editor.buffers&.values&.find { |b| b.id == bufnr }
                 end
        target ? target.keymap : editor.keymap
      end

      def resolve_modes(arg)
        if arg.respond_to?(:to_h)
          values = arg.to_h.values
          values.flat_map { |m| MODE_MAP[m.to_s] || [] }.compact.uniq
        elsif arg.is_a?(Array)
          arg.flat_map { |m| MODE_MAP[m.to_s] || [] }.compact.uniq
        else
          MODE_MAP[arg.to_s] || []
        end
      end
    end
  end
end
