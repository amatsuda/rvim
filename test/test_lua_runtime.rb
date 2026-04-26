# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestLuaRuntime < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def lua_available?
    Rvim::Lua::Runtime.available?
  end

  def test_runtime_is_lazy
    refute_nil @editor.lua
    assert_kind_of Rvim::Lua::Runtime, @editor.lua
  end

  def test_eval_simple_expression
    omit 'Lua not available on this system' unless lua_available?

    result = @editor.lua.eval('return 1 + 2')
    assert_equal 3.0, result
  end

  def test_eval_returns_strings
    omit 'Lua not available on this system' unless lua_available?

    assert_equal 'hello', @editor.lua.eval('return "hello"')
  end

  def test_eval_lua_error_surfaces_as_status_message
    omit 'Lua not available on this system' unless lua_available?

    @editor.lua.eval('error("oh no")')
    assert_match(/E5108/, @editor.status_message.to_s)
    assert_match(/oh no/, @editor.status_message.to_s)
  end

  def test_when_unavailable_eval_sets_status_message
    return if lua_available?

    @editor.lua.eval('return 1')
    assert_match(/Lua disabled/, @editor.status_message.to_s)
  end
end

class TestLuaCommands < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def lua_available?
    Rvim::Lua::Runtime.available?
  end

  def test_lua_command_evals_chunk
    omit 'Lua not available on this system' unless lua_available?

    Rvim::Command.execute(@editor, Rvim::Command.parse(':lua vim.cmd("set ts=4")'))
    assert_equal 4, @editor.settings.get(:tabstop)
  end

  def test_luafile_command_runs_file
    omit 'Lua not available on this system' unless lua_available?

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'plugin.lua')
      File.write(path, 'vim.cmd("set ts=8")')
      Rvim::Command.execute(@editor, Rvim::Command.parse(":luafile #{path}"))
      assert_equal 8, @editor.settings.get(:tabstop)
    end
  end

  def test_luafile_no_arg_errors
    Rvim::Command.execute(@editor, Rvim::Command.parse(':luafile'))
    assert_match(/E471/, @editor.status_message.to_s)
  end

  def test_luafile_missing_path_errors
    omit 'Lua not available on this system' unless lua_available?

    Rvim::Command.execute(@editor, Rvim::Command.parse(':luafile /nonexistent/path.lua'))
    assert_match(/E484/, @editor.status_message.to_s)
  end

  def test_source_dot_lua_routes_to_runtime
    omit 'Lua not available on this system' unless lua_available?

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'init.lua')
      File.write(path, 'vim.cmd("set ts=6")')
      Rvim::Command.execute(@editor, Rvim::Command.parse(":source #{path}"))
      assert_equal 6, @editor.settings.get(:tabstop)
    end
  end
end

class TestLuaCmd < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def lua_available?
    Rvim::Lua::Runtime.available?
  end

  def test_vim_cmd_runs_ex_command
    omit 'Lua not available on this system' unless lua_available?

    @editor.lua.eval('vim.cmd("set ts=10")')
    assert_equal 10, @editor.settings.get(:tabstop)
  end

  def test_vim_cmd_handles_multiline
    omit 'Lua not available on this system' unless lua_available?

    @editor.lua.eval(<<~LUA)
      vim.cmd([[
        set ts=12
        set sw=4
      ]])
    LUA
    assert_equal 12, @editor.settings.get(:tabstop)
    assert_equal 4, @editor.settings.get(:shiftwidth)
  end
end

class TestLuaNotify < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def lua_available?
    Rvim::Lua::Runtime.available?
  end

  def test_notify_default_level_sets_status
    omit 'Lua not available on this system' unless lua_available?

    @editor.lua.eval('vim.notify("hello from lua")')
    assert_equal 'hello from lua', @editor.status_message
  end

  def test_notify_with_level_tags_message
    omit 'Lua not available on this system' unless lua_available?

    @editor.lua.eval('vim.notify("ouch", vim.log.levels.ERROR)')
    assert_match(/\[ERROR\] ouch/, @editor.status_message.to_s)
  end

  def test_log_levels_table_present
    omit 'Lua not available on this system' unless lua_available?

    assert_equal 4.0, @editor.lua.eval('return vim.log.levels.ERROR')
  end
end
