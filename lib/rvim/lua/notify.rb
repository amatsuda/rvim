# frozen_string_literal: true

module Rvim
  module Lua
    # vim.notify(msg, [level], [opts]): forward a Lua plugin's notification
    # to the editor's status line. Level is one of vim.log.levels but for v3.0
    # we just stringify and route to status_message regardless of level.
    module Notify
      module_function

      LEVELS = { 0 => 'TRACE', 1 => 'DEBUG', 2 => 'INFO', 3 => 'WARN', 4 => 'ERROR' }.freeze

      def install(state, editor, _runtime)
        state.function 'vim.notify' do |msg, level, _opts|
          tag = LEVELS[level&.to_i]
          editor.status_message = tag ? "[#{tag}] #{msg}" : msg.to_s
        end

        # vim.log.levels — used by plugins to pass severity to vim.notify.
        state.eval(<<~LUA)
          vim.log = { levels = { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 } }
        LUA
      end
    end
  end
end
