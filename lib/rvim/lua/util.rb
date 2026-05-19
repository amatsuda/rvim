# frozen_string_literal: true

module Rvim
  module Lua
    # vim.tbl_* / vim.list_* / vim.split / startswith / endswith / etc.
    # Pure-Lua implementations — no Ruby callbacks needed since these are
    # table/string manipulators.
    module Util
      module_function

      # Plugins (lazy.nvim is the obvious case) hard-check `jit and
      # jit.version` and `pcall(require, "ffi")` as a "are we on
      # LuaJIT?" probe. Real NeoVim ships LuaJIT; rvim's rufus-lua
      # binding is standard Lua 5.x. We present the probe-surface so
      # version gates pass; plugins that actually call ffi.cdef et al
      # fail at use-time, which is the right place to fail (their
      # capability check would have returned true anyway on stock
      # rvim without us doing this).
      JIT_FFI_SHIM = <<~LUA.freeze
        if jit == nil then
          jit = {
            version    = "LuaJIT 2.1.0 (rvim shim)",
            version_num = 20100,
            os         = (function()
              local uv = vim.uv or vim.loop
              if uv and uv.os_uname then
                local u = uv.os_uname()
                return u and u.sysname or "Unknown"
              end
              return "Unknown"
            end)(),
            arch       = "x64",
            status     = function() return false end,
            on         = function() end,
            off        = function() end,
            flush      = function() end,
            opt        = setmetatable({}, { __index = function() return function() end end }),
          }
        end

        if package.preload["ffi"] == nil and package.loaded["ffi"] == nil then
          package.preload["ffi"] = function()
            local ffi = {
              os   = jit.os,
              arch = jit.arch,
              C    = setmetatable({}, {
                __index = function(_, name)
                  error("ffi.C." .. tostring(name) .. " unavailable in rvim (no LuaJIT)", 2)
                end,
              }),
            }
            local function nope(name)
              return function() error("ffi." .. name .. " unavailable in rvim (no LuaJIT)", 2) end
            end
            ffi.cdef    = nope("cdef")
            ffi.load    = nope("load")
            ffi.new     = nope("new")
            ffi.cast    = nope("cast")
            ffi.string  = nope("string")
            ffi.sizeof  = nope("sizeof")
            ffi.typeof  = nope("typeof")
            ffi.gc      = function(p) return p end
            ffi.copy    = nope("copy")
            ffi.fill    = nope("fill")
            ffi.errno   = function() return 0 end
            return ffi
          end
        end
      LUA

      LUA_HELPERS = <<~LUA.freeze
        function vim.tbl_isempty(t)
          if type(t) ~= "table" then return true end
          return next(t) == nil
        end

        function vim.tbl_islist(t)
          if type(t) ~= "table" then return false end
          local n = #t
          for k, _ in pairs(t) do
            if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
              return false
            end
          end
          return true
        end
        vim.islist = vim.tbl_islist

        function vim.tbl_count(t)
          local n = 0
          for _ in pairs(t) do n = n + 1 end
          return n
        end

        function vim.tbl_keys(t)
          local out = {}
          for k, _ in pairs(t) do out[#out + 1] = k end
          return out
        end

        function vim.tbl_values(t)
          local out = {}
          for _, v in pairs(t) do out[#out + 1] = v end
          return out
        end

        function vim.tbl_contains(t, value)
          for _, v in pairs(t) do
            if v == value then return true end
          end
          return false
        end

        function vim.tbl_map(f, t)
          local out = {}
          for k, v in pairs(t) do out[k] = f(v) end
          return out
        end

        function vim.tbl_filter(f, t)
          local out = {}
          for _, v in pairs(t) do
            if f(v) then out[#out + 1] = v end
          end
          return out
        end

        function vim.tbl_get(t, ...)
          local cur = t
          local keys = {...}
          for i = 1, #keys do
            if type(cur) ~= "table" then return nil end
            cur = cur[keys[i]]
            if cur == nil then return nil end
          end
          return cur
        end

        function vim.tbl_extend(behavior, ...)
          local out = {}
          local args = {...}
          for i = 1, #args do
            local src = args[i]
            for k, v in pairs(src) do
              if behavior == "force" or out[k] == nil then
                out[k] = v
              elseif behavior == "error" and out[k] ~= nil then
                error("key conflict: " .. tostring(k))
              end
            end
          end
          return out
        end

        function vim.tbl_deep_extend(behavior, ...)
          local function deep_extend(out, src)
            for k, v in pairs(src) do
              if type(v) == "table" and type(out[k]) == "table" then
                deep_extend(out[k], v)
              elseif behavior == "force" or out[k] == nil then
                out[k] = v
              elseif behavior == "error" and out[k] ~= nil then
                error("key conflict: " .. tostring(k))
              end
            end
            return out
          end

          local out = {}
          local args = {...}
          for i = 1, #args do deep_extend(out, args[i]) end
          return out
        end

        function vim.list_extend(dst, src, start, finish)
          start = start or 1
          finish = finish or #src
          for i = start, finish do dst[#dst + 1] = src[i] end
          return dst
        end

        function vim.deepcopy(t)
          if type(t) ~= "table" then return t end
          local out = {}
          for k, v in pairs(t) do out[k] = vim.deepcopy(v) end
          return out
        end

        function vim.split(s, sep, opts)
          opts = opts or {}
          local out = {}
          local plain = opts.plain
          local trimempty = opts.trimempty
          local pattern = plain and (sep:gsub("(%W)", "%%%1")) or sep
          local i = 1
          while i <= #s + 1 do
            local a, b = string.find(s, pattern, i)
            if not a then
              out[#out + 1] = string.sub(s, i)
              break
            end
            out[#out + 1] = string.sub(s, i, a - 1)
            i = b + 1
          end
          if trimempty then
            while #out > 0 and out[1] == "" do table.remove(out, 1) end
            while #out > 0 and out[#out] == "" do table.remove(out) end
          end
          return out
        end

        function vim.startswith(s, prefix)
          return string.sub(s, 1, #prefix) == prefix
        end

        function vim.endswith(s, suffix)
          if #suffix == 0 then return true end
          return string.sub(s, -#suffix) == suffix
        end

        function vim.trim(s)
          return (s:gsub("^%s+", ""):gsub("%s+$", ""))
        end

        function vim.inspect(v)
          if type(v) == "string" then return string.format("%q", v) end
          if type(v) ~= "table" then return tostring(v) end
          local parts = {}
          for k, val in pairs(v) do
            parts[#parts + 1] = tostring(k) .. " = " .. vim.inspect(val)
          end
          return "{ " .. table.concat(parts, ", ") .. " }"
        end

        function vim.print(...)
          local args = {...}
          for i = 1, select("#", ...) do
            args[i] = vim.inspect(args[i])
          end
          vim.notify(table.concat(args, "\\t"))
        end

        -- vim.health — :checkhealth dispatch surface. Plugins capture
        -- vim.health.start/ok/warn/error/info at module-load time and
        -- call them later when the user runs :checkhealth. We're not
        -- wiring up :checkhealth yet, so these stay as no-ops.
        vim.health = vim.health or {}
        vim.health.start = vim.health.start or function(_) end
        vim.health.ok    = vim.health.ok    or function(_) end
        vim.health.warn  = vim.health.warn  or function(_, _) end
        vim.health.error = vim.health.error or function(_, _) end
        vim.health.info  = vim.health.info  or function(_) end
        vim.health.report_start = vim.health.start
        vim.health.report_ok    = vim.health.ok
        vim.health.report_warn  = vim.health.warn
        vim.health.report_error = vim.health.error
        vim.health.report_info  = vim.health.info

        -- vim.F — function helpers; lazy uses vim.F.pack_len/unpack_len.
        vim.F = vim.F or {}
        function vim.F.pack_len(...)
          return { n = select("#", ...), ... }
        end
        function vim.F.unpack_len(t)
          local _unpack = table.unpack or unpack
          return _unpack(t, 1, t.n)
        end
        function vim.F.if_nil(v, default) if v == nil then return default else return v end end

        -- vim.in_fast_event — true while running inside a libuv fast
        -- callback (where most vim.* calls are forbidden). rvim has
        -- no real libuv loop, so we're never in one.
        function vim.in_fast_event() return false end

        -- vim.is_callable — type-check helper.
        function vim.is_callable(f)
          if type(f) == "function" then return true end
          if type(f) == "table" then
            local mt = getmetatable(f)
            return mt ~= nil and type(mt.__call) == "function"
          end
          return false
        end

        -- vim.regex — compile a vim pattern. We don't translate vim
        -- regex to Lua patterns; return a stub that match_str returns
        -- nil. Plugins that depend on actual matching will need a
        -- real impl later, but most just check for presence.
        function vim.regex(_pattern)
          return {
            match_str = function(_, _) return nil end,
            match_line = function(_, _, _) return nil end,
          }
        end
      LUA

      def install(state, _editor, _runtime)
        state.eval(LUA_HELPERS)
        state.eval(JIT_FFI_SHIM)
      end
    end
  end
end
