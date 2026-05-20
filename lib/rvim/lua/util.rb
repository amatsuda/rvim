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

        function vim.list_slice(list, start, finish)
          start = start or 1
          finish = finish or #list
          if start < 0 then start = #list + 1 + start end
          if finish < 0 then finish = #list + 1 + finish end
          local out = {}
          for i = start, finish do out[#out + 1] = list[i] end
          return out
        end

        function vim.list_contains(list, value)
          for _, v in ipairs(list) do
            if v == value then return true end
          end
          return false
        end

        function vim.deepcopy(t)
          if type(t) ~= "table" then return t end
          local out = {}
          for k, v in pairs(t) do out[k] = vim.deepcopy(v) end
          return out
        end

        function vim.deep_equal(a, b)
          if a == b then return true end
          if type(a) ~= "table" or type(b) ~= "table" then return false end
          for k, v in pairs(a) do
            if not vim.deep_equal(v, b[k]) then return false end
          end
          for k, _ in pairs(b) do
            if a[k] == nil then return false end
          end
          return true
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

        -- vim.health — :checkhealth dispatch surface. Plugins call
        -- vim.health.start/ok/warn/error/info from a health.check()
        -- function; we accumulate into _collected so :checkhealth in
        -- Ruby can read it back and render.
        vim.health = vim.health or {}
        vim.health._collected = vim.health._collected or {}

        local function _emit(kind, msg, advice)
          table.insert(vim.health._collected, {
            kind = kind,
            msg  = tostring(msg or ""),
            advice = advice,
          })
        end

        vim.health.start = function(name) _emit("start", name) end
        vim.health.ok    = function(msg)  _emit("ok",    msg) end
        vim.health.warn  = function(msg, advice) _emit("warn",  msg, advice) end
        vim.health.error = function(msg, advice) _emit("error", msg, advice) end
        vim.health.info  = function(msg)  _emit("info",  msg) end
        vim.health.report_start = vim.health.start
        vim.health.report_ok    = vim.health.ok
        vim.health.report_warn  = vim.health.warn
        vim.health.report_error = vim.health.error
        vim.health.report_info  = vim.health.info

        -- Run a single health module's check() and return a flat
        -- array suitable for Ruby pushback. Each entry is
        -- {kind, msg, advice_or_""}.
        function vim.health._run(modname)
          vim.health._collected = {}
          local ok, mod = pcall(require, modname)
          if not ok then
            return { { kind = "error", msg = "failed to load " .. modname .. ": " .. tostring(mod), advice = "" } }
          end
          if type(mod) ~= "table" or type(mod.check) ~= "function" then
            return { { kind = "error", msg = modname .. " has no check() function", advice = "" } }
          end
          local ok2, err = pcall(mod.check)
          if not ok2 then
            table.insert(vim.health._collected, { kind = "error", msg = "check() crashed: " .. tostring(err), advice = "" })
          end
          -- Return a copy with advice normalized — Rufus can't push
          -- back nested tables of mixed types cleanly otherwise.
          local out = {}
          for i, e in ipairs(vim.health._collected) do
            local advice_str = ""
            if type(e.advice) == "table" then
              advice_str = table.concat(e.advice, "\\n")
            elseif e.advice ~= nil then
              advice_str = tostring(e.advice)
            end
            out[i] = { kind = e.kind, msg = e.msg, advice = advice_str }
          end
          vim.health._collected = {}
          return out
        end

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

        -- vim.hl — nvim 0.11+ namespace replacing vim.highlight.
        -- range(bufnr, ns, hl_group, start, end[, opts]) lights up a
        -- byte range with the given group. We forward to extmarks.
        vim.hl = vim.hl or {}
        function vim.hl.range(bufnr, ns, hl_group, start, finish, opts)
          opts = opts or {}
          if start and finish then
            local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, start[1], start[2], {
              end_row = finish[1], end_col = finish[2],
              hl_group = hl_group, priority = opts.priority or 100,
            })
            return ok
          end
        end
        function vim.hl.on_yank(_opts) end
        vim.highlight = vim.highlight or vim.hl

        -- io.popen — LuaJIT's built-in popen is broken in rvim's
        -- embedded environment: read("*a") returns nil because the
        -- child's stdout never gets fully drained before close().
        -- Replace with a handle backed by vim.fn.system, which runs
        -- the command to completion and gives us the full output up
        -- front. Plugins like telescope.health rely on read("*a").
        if not io.popen or true then
          local orig_popen = io.popen
          io.popen = function(cmd, _mode)
            local out = vim.fn.system(cmd)
            local exit = vim.v.shell_error or 0
            local h = { _data = out or "", _exit = exit, _closed = false }
            function h:read(fmt)
              if self._closed then return nil end
              fmt = fmt or "*l"
              if fmt == "*a" or fmt == "a" then
                local rest = self._data
                self._data = ""
                return rest
              elseif fmt == "*l" or fmt == "l" or fmt == "*L" or fmt == "L" then
                if #self._data == 0 then return nil end
                local nl = self._data:find("\\n", 1, true)
                if nl then
                  local line = self._data:sub(1, nl - (fmt == "*L" and 0 or 1))
                  self._data = self._data:sub(nl + 1)
                  return line
                end
                local rest = self._data
                self._data = ""
                return rest
              elseif fmt == "*n" or fmt == "n" then
                local m = self._data:match("^%s*(%-?%d+%.?%d*)")
                if m then self._data = self._data:sub(#m + 1); return tonumber(m) end
                return nil
              elseif type(fmt) == "number" then
                if #self._data == 0 then return nil end
                local chunk = self._data:sub(1, fmt)
                self._data = self._data:sub(fmt + 1)
                return chunk
              end
              return nil
            end
            function h:lines() return function() return self:read("*l") end end
            function h:close() self._closed = true; return true, "exit", self._exit end
            function h:write(_) return nil end  -- read-only
            return h
          end
        end

        -- vim.in_fast_event — true while running inside a libuv fast
        -- callback (where most vim.* calls are forbidden). rvim has
        -- no real libuv loop, so we're never in one.
        function vim.in_fast_event() return false end

        -- vim.validate — type-check helper. Two signatures:
        --   * Legacy (pre-0.11):  vim.validate({ name = {value, type[, optional]}, ... })
        --   * Positional (0.11+): vim.validate(name, value, type[, message_or_optional])
        local function _validate_one(name, value, expected, optional)
          if value == nil then
            if not optional then
              error("validate: " .. tostring(name) .. " is required", 3)
            end
            return
          end
          if type(expected) == "string" then
            if expected ~= "any" and type(value) ~= expected then
              error("validate: " .. tostring(name) .. " expected " .. expected ..
                    ", got " .. type(value), 3)
            end
          elseif type(expected) == "function" then
            if not expected(value) then
              error("validate: " .. tostring(name) .. " failed predicate", 3)
            end
          end
        end

        function vim.validate(a, b, c, d)
          if type(a) == "string" then
            -- Positional form. d is either a message (string) or
            -- optional (bool) depending on caller; treat both safely.
            local optional = (d == true)
            _validate_one(a, b, c, optional)
            return true
          end

          if type(a) == "table" then
            for name, spec in pairs(a) do
              if type(spec) == "table" then
                _validate_one(name, spec[1], spec[2], spec[3])
              end
            end
            return true
          end
          return true
        end

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
