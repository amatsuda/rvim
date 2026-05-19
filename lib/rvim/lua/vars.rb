# frozen_string_literal: true

module Rvim
  module Lua
    # vim.g / vim.b / vim.w / vim.t — variable namespaces.
    #
    # vim.g.foo = 1 sets a global var (writes through to editor.let_vars).
    # vim.b / vim.w / vim.t target the current buffer / window / tab's @vars
    # hash. Reads return nil when the key is unset (matching NeoVim).
    module Vars
      module_function

      def install(state, editor, _runtime)
        # vim.v — vim "v:" predefined vars. Plugins read v:progpath /
        # v:argv / v:version; rare to write. We expose a fixed set.
        v_vars = {
          'progpath' => $PROGRAM_NAME,
          'argv'     => ARGV.dup,
          'version'  => 802,
          'errmsg'   => '',
          'shell_error' => 0,
          'true'     => true,
          'false'    => false,
          'null'     => nil,
          't_number' => 0, 't_string' => 1, 't_func' => 2, 't_list' => 3,
          't_dict'   => 4, 't_float'  => 5, 't_bool' => 6, 't_none' => 7,
        }
        state.function '_rvim_v_set'  do |name, value| v_vars[name.to_s] = value end
        state.function '_rvim_v_get'  do |name| v_vars[name.to_s] end

        # vim.env — process environment as a magic table.
        state.function '_rvim_env_set' do |name, value|
          if value.nil?
            ENV.delete(name.to_s)
          else
            ENV[name.to_s] = value.to_s
          end
        end
        state.function '_rvim_env_get' do |name| ENV[name.to_s] end

        state.function '_rvim_g_set'  do |name, value| editor.let_vars[name.to_s] = value end
        state.function '_rvim_g_get'  do |name| editor.let_vars[name.to_s] end
        state.function '_rvim_b_set'  do |name, value| (editor.current_buffer&.vars || {})[name.to_s] = value end
        state.function '_rvim_b_get'  do |name| editor.current_buffer&.vars&.[](name.to_s) end
        state.function '_rvim_w_set'  do |name, value| (editor.current_window&.vars ||= {})[name.to_s] = value end
        state.function '_rvim_w_get'  do |name| editor.current_window&.vars&.[](name.to_s) end
        state.function '_rvim_t_set'  do |name, value| (editor.current_tab&.vars ||= {})[name.to_s] = value end
        state.function '_rvim_t_get'  do |name| editor.current_tab&.vars&.[](name.to_s) end

        state.eval(<<~LUA)
          local function make_var_table(setter, getter)
            return setmetatable({}, {
              __index = function(_, name) return getter(name) end,
              __newindex = function(_, name, value) setter(name, value) end,
            })
          end

          vim.g = make_var_table(_rvim_g_set, _rvim_g_get)
          vim.b = make_var_table(_rvim_b_set, _rvim_b_get)
          vim.w = make_var_table(_rvim_w_set, _rvim_w_get)
          vim.t = make_var_table(_rvim_t_set, _rvim_t_get)
          vim.v = make_var_table(_rvim_v_set, _rvim_v_get)
          vim.env = make_var_table(_rvim_env_set, _rvim_env_get)
        LUA
      end
    end
  end
end
