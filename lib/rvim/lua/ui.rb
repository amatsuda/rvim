# frozen_string_literal: true

module Rvim
  module Lua
    # vim.ui.input / vim.ui.select — modal input prompts.
    #
    # NeoVim's default implementations block on user input via vim.fn.input()
    # / inputlist(). Without integrating into the editor's interactive loop
    # we can't do that here, so v3.10 ships:
    #
    #   - synchronous fallbacks that call the callback with the default value
    #     (or nil) immediately. This matches NeoVim's "no UI provider" path.
    #   - vim.ui.input / vim.ui.select are *replaceable* — plugins like
    #     dressing.nvim re-assign these tables, and that override mechanism
    #     works the same way here.
    #
    # Tests cover the default fallback path AND the override path.
    module Ui
      module_function

      def install(state, _editor, _runtime)
        state.eval(<<~LUA)
          vim.ui = vim.ui or {}

          function vim.ui.input(opts, on_confirm)
            opts = opts or {}
            local default = opts.default
            if on_confirm then on_confirm(default) end
          end

          function vim.ui.select(items, opts, on_choice)
            opts = opts or {}
            -- Default: pick first item if available; else nil.
            if on_choice then
              if items and items[1] ~= nil then
                on_choice(items[1], 1)
              else
                on_choice(nil, nil)
              end
            end
          end
        LUA
      end
    end
  end
end
