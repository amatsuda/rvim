# frozen_string_literal: true

module Rvim
  module Lua
    # vim.fs — path helpers + a directory walker. lazy.nvim uses
    # vim.fs.find to locate a plugin's `lua/` subdir and vim.fs.normalize
    # to canonicalize user-supplied paths before stat'ing them.
    #
    # We piggyback on vim.loop.fs_scandir for the actual directory
    # walk so plugins that subclass / replace vim.loop see consistent
    # behavior.
    module Fs
      module_function

      LUA_HELPERS = <<~LUA.freeze
        vim.fs = vim.fs or {}

        function vim.fs.basename(path)
          if path == nil or path == "" then return path end
          return (string.gsub(path, "(.*/)(.*)", "%2"))
        end

        function vim.fs.dirname(path)
          if path == nil or path == "" then return "." end
          if not string.find(path, "/") then return "." end
          local dir = string.gsub(path, "/[^/]*$", "")
          if dir == "" then return "/" end
          return dir
        end

        function vim.fs.joinpath(...)
          local parts = {...}
          if #parts == 0 then return "" end
          local out = ""
          for i = 1, #parts do
            local p = parts[i]
            if p ~= nil and p ~= "" then
              if string.sub(p, 1, 1) == "/" then
                -- Absolute later parts reset (matches NeoVim).
                out = p
              elseif out == "" then
                out = p
              else
                if out:sub(-1) ~= "/" then out = out .. "/" end
                out = out .. p
              end
            end
          end
          return out
        end

        function vim.fs.normalize(path, opts)
          opts = opts or {}
          if path == nil or path == "" then return path end
          -- Expand ~ and $VAR.
          if string.sub(path, 1, 1) == "~" then
            local home = (vim.loop and vim.loop.os_homedir and vim.loop.os_homedir()) or os.getenv("HOME") or ""
            path = home .. string.sub(path, 2)
          end
          -- %w doesn't include underscore in Lua; env var names do.
          path = string.gsub(path, "%$([%w_]+)", function(name)
            return os.getenv(name) or ("$" .. name)
          end)
          -- Collapse repeated slashes.
          path = string.gsub(path, "//+", "/")
          -- Drop trailing slash (but not on the root "/").
          if #path > 1 and string.sub(path, -1) == "/" then
            path = string.sub(path, 1, -2)
          end
          return path
        end

        -- vim.fs.find(names, opts) -> { path, ... }
        --   names: string | string[] | function(name, path) -> bool
        --   opts.path:    starting directory (default cwd)
        --   opts.upward:  bool — walk up to root looking for matches
        --   opts.type:    "file" | "directory" | "link"
        --   opts.limit:   max number of matches (default 1)
        --   opts.stop:    string — directory at which to stop the upward walk
        function vim.fs.find(names, opts)
          opts = opts or {}
          if type(names) == "string" then names = { names } end
          local limit = opts.limit or 1
          local out = {}

          local function match_name(name)
            if type(names) == "function" then return names(name, nil) end
            for _, n in ipairs(names) do if n == name then return true end end
            return false
          end

          local function add_entry(parent, name, kind)
            if opts.type and kind ~= opts.type then return false end
            local full = vim.fs.joinpath(parent, name)
            out[#out + 1] = full
            return #out >= limit
          end

          local start = opts.path or (vim.loop and vim.loop.cwd and vim.loop.cwd()) or "."
          if opts.upward then
            local dir = start
            while true do
              local h = vim.loop.fs_scandir(dir)
              if h then
                while true do
                  local name, kind = vim.loop.fs_scandir_next(h)
                  if name == nil then break end
                  if match_name(name) and add_entry(dir, name, kind) then return out end
                end
              end
              if opts.stop and dir == opts.stop then break end
              local parent = vim.fs.dirname(dir)
              if parent == dir then break end
              dir = parent
            end
            return out
          end

          -- Downward BFS walk.
          local queue = { start }
          while #queue > 0 do
            local dir = table.remove(queue, 1)
            local h = vim.loop.fs_scandir(dir)
            if h then
              while true do
                local name, kind = vim.loop.fs_scandir_next(h)
                if name == nil then break end
                if match_name(name) and add_entry(dir, name, kind) then return out end
                if kind == "directory" then
                  queue[#queue + 1] = vim.fs.joinpath(dir, name)
                end
              end
            end
          end
          return out
        end
      LUA

      def install(state, _editor, _runtime)
        state.eval(LUA_HELPERS)
      end
    end
  end
end
