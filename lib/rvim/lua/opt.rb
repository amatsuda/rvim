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

      # Comma-separated options whose Lua value is an array of paths.
      # Setting `vim.opt.rtp = { "/a", "/b" }` must store the joined
      # form so subsequent string consumers (Loader.refresh,
      # vim.opt.rtp:prepend, the editor's own runtimepath split) see
      # what they expect.
      LIST_OPTS = %w[runtimepath rtp packpath path tags wildignore
                     backupdir directory undodir cdpath].freeze

      def install(state, editor, _runtime)
        # Global setter/getter — used by both vim.opt and vim.go.
        state.function '_rvim_opt_set' do |name, value|
          coerced = coerce_to_setting(name.to_s, value)
          editor.settings.set(name.to_s, coerced)
        end

        state.function '_rvim_opt_get' do |name|
          editor.settings.get(name.to_s)
        end

        # Buffer-local setter/getter.
        state.function '_rvim_bo_set' do |name, value|
          coerced = coerce_to_setting(name.to_s, value)
          editor.settings.set(name.to_s, coerced, buffer: editor.current_buffer)
        end

        state.function '_rvim_bo_get' do |name|
          editor.settings.get(name.to_s, buffer: editor.current_buffer)
        end

        state.eval(<<~LUA)
          -- Comma-merge two option values for list-style options (clipboard,
          -- runtimepath, fillchars, etc.). For booleans / numbers we just
          -- replace.
          local function merge_csv(current, addition, mode)
            current = current or ""
            if type(current) ~= "string" or type(addition) ~= "string" then
              return addition
            end
            local parts = {}
            local seen = {}
            local function push(s)
              if s == nil or s == "" then return end
              if not seen[s] then table.insert(parts, s); seen[s] = true end
            end
            if mode == "append" then
              for v in string.gmatch(current, "([^,]+)") do push(v) end
              for v in string.gmatch(addition, "([^,]+)") do push(v) end
            elseif mode == "prepend" then
              for v in string.gmatch(addition, "([^,]+)") do push(v) end
              for v in string.gmatch(current, "([^,]+)") do push(v) end
            elseif mode == "remove" then
              local drop = {}
              for v in string.gmatch(addition, "([^,]+)") do drop[v] = true end
              for v in string.gmatch(current, "([^,]+)") do
                if not drop[v] then push(v) end
              end
            end
            return table.concat(parts, ",")
          end

          -- List-style options whose :get() should yield string[].
          -- vim.opt.rtp:get() returns paths; many plugins iterate it.
          local LIST_OPTS = {
            runtimepath = ",", rtp = ",",
            packpath = ",",
            path = ",",
            tags = ",",
            wildignore = ",",
            backupdir = ",",
            directory = ",",
            undodir = ",",
            cdpath = ",",
          }

          local function split_csv(s, sep)
            local out = {}
            if s == nil or s == "" then return out end
            for v in string.gmatch(s, "([^" .. sep .. "]+)") do
              table.insert(out, v)
            end
            return out
          end

          local function make_opt(setter, getter)
            return setmetatable({}, {
              __index = function(_, name)
                local function refresh() return getter(name) end
                local self = { _name = name }
                return setmetatable(self, {
                  __index = function(_, key)
                    if key == "get" then
                      return function()
                        local v = refresh()
                        local sep = LIST_OPTS[name]
                        if sep and type(v) == "string" then
                          return split_csv(v, sep)
                        end
                        return v
                      end
                    elseif key == "append" then
                      return function(_, v) setter(name, merge_csv(refresh(), v, "append")) end
                    elseif key == "prepend" then
                      return function(_, v) setter(name, merge_csv(refresh(), v, "prepend")) end
                    elseif key == "remove" then
                      return function(_, v) setter(name, merge_csv(refresh(), v, "remove")) end
                    end
                    return nil
                  end,
                  -- Allow `vim.opt.clipboard = vim.opt.clipboard + "x"` etc.
                  __add = function(a, b) return merge_csv(refresh(), b, "append") end,
                  __sub = function(a, b) return merge_csv(refresh(), b, "remove") end,
                  __concat = function(a, b) return merge_csv(refresh(), b, "append") end,
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

          -- vim.o — simple table-style access, no :get() wrapper.
          -- Returns raw values; identical to vim.go for globals.
          vim.o = setmetatable({}, {
            __index = function(_, name) return _rvim_opt_get(name) end,
            __newindex = function(_, name, value) _rvim_opt_set(name, value) end,
          })
        LUA
      end

      def coerce_to_setting(name, value)
        # List-style options arrive as Rufus::Lua::Table (incoming
        # Lua-side tables aren't auto-demoted; only outgoing ones
        # are). Convert to Ruby Array, then join. Existing
        # string-based readers (Loader.refresh, the editor's rtp
        # split) keep working.
        if LIST_OPTS.include?(name)
          arr = lua_table_to_array(value)
          return arr.compact.join(',') if arr
        end

        case value
        when Float then value == value.to_i ? value.to_i : value
        else value
        end
      end

      def lua_table_to_array(value)
        return value if value.is_a?(Array)
        return nil unless value.respond_to?(:to_h)

        h = value.to_h
        return [] if h.empty?

        (1..h.size).map { |i| (h[i] || h[i.to_f])&.to_s }
      end
    end
  end
end
