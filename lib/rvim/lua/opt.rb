# frozen_string_literal: true

module Rvim
  module Lua
    # vim.opt / vim.bo / vim.wo / vim.go — option proxies.
    #
    # NeoVim differentiates by scope:
    #   vim.opt.{name}  — set both global + local effective value
    #   vim.go.{name}   — global only
    #   vim.bo.{name}   — buffer-local
    #   vim.wo.{name}   — window-local
    #
    # Plugins that write `vim.opt.tabstop = 4` and read `vim.opt.tabstop:get()`
    # must round-trip cleanly. We expose `:get()` as a tiny accessor; for v3.1
    # we don't yet implement the OptionInfo chain (append/prepend/remove on
    # list-style options) — that's a later ship if a plugin needs it.
    module Opt
      module_function

      def install(state, editor, _runtime)
        # Global setter/getter — used by both vim.opt and vim.go.
        state.function '_rvim_opt_set' do |name, value|
          coerced = coerce_to_setting(value)
          editor.settings.set(name.to_s, coerced)
        end

        state.function '_rvim_opt_get' do |name|
          editor.settings.get(name.to_s)
        end

        # Buffer-local setter/getter.
        state.function '_rvim_bo_set' do |name, value|
          coerced = coerce_to_setting(value)
          editor.settings.set(name.to_s, coerced, buffer: editor.current_buffer)
        end

        state.function '_rvim_bo_get' do |name|
          editor.settings.get(name.to_s, buffer: editor.current_buffer)
        end

        state.eval(<<~LUA)
          local function make_opt(setter, getter)
            return setmetatable({}, {
              __index = function(_, name)
                local value = getter(name)
                return setmetatable({ _name = name, _value = value }, {
                  __index = function(self, key)
                    if key == 'get' then
                      return function() return getter(self._name) end
                    end
                    return rawget(self, key)
                  end,
                })
              end,
              __newindex = function(_, name, value)
                setter(name, value)
              end,
            })
          end

          vim.opt = make_opt(_rvim_opt_set, _rvim_opt_get)
          vim.go  = make_opt(_rvim_opt_set, _rvim_opt_get)
          vim.bo  = make_opt(_rvim_bo_set,  _rvim_bo_get)
          vim.wo  = make_opt(_rvim_opt_set, _rvim_opt_get)  -- window-local stubs to global
        LUA
      end

      def coerce_to_setting(value)
        case value
        when Float then value == value.to_i ? value.to_i : value
        else value
        end
      end
    end
  end
end
