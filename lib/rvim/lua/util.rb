# frozen_string_literal: true

module Rvim
  module Lua
    # vim.tbl_* / vim.list_* / vim.split / startswith / endswith / etc.
    # Pure-Lua implementations — no Ruby callbacks needed since these are
    # table/string manipulators.
    module Util
      module_function

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
      LUA

      def install(state, _editor, _runtime)
        state.eval(LUA_HELPERS)
      end
    end
  end
end
