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
        state.function 'vim.cmd' do |arg|
          run(editor, arg)
        end
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
