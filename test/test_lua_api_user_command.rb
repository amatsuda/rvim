# frozen_string_literal: true

require_relative 'test_helper'

# vim.api.nvim_create_user_command / nvim_del_user_command —
# lazy.nvim's :Lazy entrypoint and most plugin :Foo commands are
# registered through this. The string-body form delegates to the
# existing :command body machinery; the function-callback form is
# new and is what NeoVim plugins overwhelmingly use today.

class TestLuaApiUserCommand < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_create_user_command_with_string_body_registers
    @editor.lua.eval('vim.api.nvim_create_user_command("Greet", "echo hi", {})')
    uc = @editor.user_commands['Greet']
    assert_not_nil uc
    assert_equal 'Greet', uc.name
    assert_equal 'echo hi', uc.body
  end

  def test_create_user_command_with_function_callback_invokes_on_dispatch
    @editor.lua.eval(<<~LUA)
      hits = 0
      received_args = ""
      vim.api.nvim_create_user_command("Trigger", function(opts)
        hits = hits + 1
        received_args = opts.args
      end, { nargs = "*" })
    LUA
    parsed = Rvim::Command.parse(':Trigger one two')
    Rvim::Command.execute(@editor, parsed)
    assert_equal 1, @editor.lua.eval('return hits').to_i
    assert_equal 'one two', @editor.lua.eval('return received_args')
  end

  def test_callback_receives_fargs_split
    @editor.lua.eval(<<~LUA)
      seen = ""
      vim.api.nvim_create_user_command("Split", function(opts)
        seen = table.concat(opts.fargs, "|")
      end, { nargs = "+" })
    LUA
    parsed = Rvim::Command.parse(':Split a  b c')
    Rvim::Command.execute(@editor, parsed)
    assert_equal 'a|b|c', @editor.lua.eval('return seen')
  end

  def test_callback_receives_bang
    @editor.lua.eval(<<~LUA)
      got_bang = nil
      vim.api.nvim_create_user_command("Bangy", function(opts)
        got_bang = opts.bang
      end, { bang = true })
    LUA
    parsed = Rvim::Command.parse(':Bangy!')
    Rvim::Command.execute(@editor, parsed)
    assert_equal true, @editor.lua.eval('return got_bang')
  end

  def test_del_user_command_removes_entry
    @editor.lua.eval('vim.api.nvim_create_user_command("Doomed", "echo x", {})')
    assert @editor.user_commands.key?('Doomed')
    @editor.lua.eval('vim.api.nvim_del_user_command("Doomed")')
    refute @editor.user_commands.key?('Doomed')
  end

  def test_callback_exception_does_not_crash_dispatch
    @editor.lua.eval(<<~LUA)
      vim.api.nvim_create_user_command("Boom", function() error("nope") end, {})
    LUA
    parsed = Rvim::Command.parse(':Boom')
    assert_nothing_raised { Rvim::Command.execute(@editor, parsed) }
  end

  def test_string_body_still_supports_args_placeholder
    seen = []
    @editor.define_singleton_method(:open) { |path| seen << path }
    @editor.lua.eval('vim.api.nvim_create_user_command("OpenIt", "edit <args>", { nargs = "1" })')
    parsed = Rvim::Command.parse(':OpenIt /tmp/foo')
    Rvim::Command.execute(@editor, parsed)
    assert_equal ['/tmp/foo'], seen
  end
end
