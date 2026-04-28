# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestLuaLoader < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    @tmp = Dir.mktmpdir('rvim-lua-rtp')
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
  end

  def test_require_loads_module_from_runtimepath
    FileUtils.mkdir_p(File.join(@tmp, 'lua'))
    File.write(File.join(@tmp, 'lua', 'mymod.lua'), 'return { hello = function() return "world" end }')
    @editor.settings.set(:runtimepath, @tmp)
    Rvim::Lua::Loader.refresh(@editor.lua.state, @editor)
    result = @editor.lua.eval('return require("mymod").hello()')
    assert_equal 'world', result
  end

  def test_require_loads_dotted_module
    FileUtils.mkdir_p(File.join(@tmp, 'lua', 'pkg'))
    File.write(File.join(@tmp, 'lua', 'pkg', 'inner.lua'), 'return { v = 42 }')
    @editor.settings.set(:runtimepath, @tmp)
    Rvim::Lua::Loader.refresh(@editor.lua.state, @editor)
    result = @editor.lua.eval('return require("pkg.inner").v')
    assert_equal 42, result.to_i
  end

  def test_require_uses_init_lua_for_packages
    FileUtils.mkdir_p(File.join(@tmp, 'lua', 'mypkg'))
    File.write(File.join(@tmp, 'lua', 'mypkg', 'init.lua'), 'return { tag = "init" }')
    @editor.settings.set(:runtimepath, @tmp)
    Rvim::Lua::Loader.refresh(@editor.lua.state, @editor)
    result = @editor.lua.eval('return require("mypkg").tag')
    assert_equal 'init', result
  end

  def test_package_loaded_caches
    FileUtils.mkdir_p(File.join(@tmp, 'lua'))
    counter_file = File.join(@tmp, 'lua', 'counter.lua')
    File.write(counter_file, 'return os.time()')
    @editor.settings.set(:runtimepath, @tmp)
    Rvim::Lua::Loader.refresh(@editor.lua.state, @editor)
    a = @editor.lua.eval('return require("counter")')
    b = @editor.lua.eval('return require("counter")')
    assert_equal a, b
  end

  def test_vim_loader_stub_present
    refute_nil @editor.lua.eval('return vim.loader')
    @editor.lua.eval('vim.loader.enable()') # no-op, must not error
  end

  def test_missing_module_raises_lua_error
    @editor.lua.eval('require("nonexistent_xyz")')
    assert_match(/E5108/, @editor.status_message.to_s)
  end
end
