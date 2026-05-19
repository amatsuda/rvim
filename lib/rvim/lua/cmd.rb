# frozen_string_literal: true

module Rvim
  module Lua
    # vim.cmd("..."): run an ex command, just like `:` from a Lua plugin.
    # NeoVim also supports vim.cmd as a callable table where vim.cmd.echo("hi")
    # works. v3.0 supports the call-as-function form; the dotted form is
    # added in a later ship.
    module Cmd
      module_function

      def install(state, editor, _runtime)
        state.function '_rvim_cmd_run' do |arg|
          run(editor, arg)
        end

        # vim.cmd needs both shapes:
        #   vim.cmd("echo hi")            — call as function
        #   vim.cmd.colorscheme("foo")    — table-indexed verb form
        #   vim.cmd.colorscheme "foo"     — same, ex-style
        #   vim.cmd { cmd = "edit", args = {"foo"} }  — structured form
        state.eval(<<~LUA)
          local function flatten_args(args)
            local parts = {}
            for i = 1, #args do
              local v = args[i]
              if type(v) == "table" then
                for j = 1, #v do parts[#parts + 1] = tostring(v[j]) end
              else
                parts[#parts + 1] = tostring(v)
              end
            end
            return table.concat(parts, " ")
          end

          local function run_structured(spec)
            local line = spec.cmd or ""
            if spec.bang then line = line .. "!" end
            if spec.args then line = line .. " " .. flatten_args(spec.args) end
            _rvim_cmd_run(line)
          end

          vim.cmd = setmetatable({}, {
            __call = function(_, arg)
              if type(arg) == "table" then
                run_structured(arg)
              else
                _rvim_cmd_run(arg)
              end
            end,
            __index = function(_, verb)
              return function(...)
                local args = {...}
                if #args == 1 and type(args[1]) == "table" then
                  local t = args[1]
                  t.cmd = verb
                  run_structured(t)
                else
                  local line = verb
                  if #args > 0 then line = line .. " " .. flatten_args(args) end
                  _rvim_cmd_run(line)
                end
              end
            end,
          })
        LUA
      end

      def run(editor, arg)
        line = arg.to_s
        return if line.empty?

        # Split on newlines so a Lua heredoc with multiple commands works.
        line.each_line do |single|
          single = single.chomp.strip
          next if single.empty?

          parsed = Rvim::Command.parse(single)
          Rvim::Command.execute(editor, parsed) if parsed
        end
      end
    end
  end
end
