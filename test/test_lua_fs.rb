# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestLuaFs < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    @tmp = Dir.mktmpdir('rvim-fs-')
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.exist?(@tmp)
  end

  def test_basename
    assert_equal 'x.lua', @editor.lua.eval('return vim.fs.basename("/a/b/x.lua")')
    assert_equal 'x.lua', @editor.lua.eval('return vim.fs.basename("x.lua")')
  end

  def test_dirname
    assert_equal '/a/b', @editor.lua.eval('return vim.fs.dirname("/a/b/x.lua")')
    assert_equal '/',    @editor.lua.eval('return vim.fs.dirname("/x")')
    assert_equal '.',    @editor.lua.eval('return vim.fs.dirname("x")')
  end

  def test_joinpath
    assert_equal '/a/b/c', @editor.lua.eval('return vim.fs.joinpath("/a", "b", "c")')
    assert_equal 'a/b',    @editor.lua.eval('return vim.fs.joinpath("a/", "b")')
    assert_equal '/abs',   @editor.lua.eval('return vim.fs.joinpath("/ignored", "/abs")')
  end

  def test_normalize_tilde
    res = @editor.lua.eval('return vim.fs.normalize("~/foo")')
    assert_equal File.join(Dir.home, 'foo'), res
  end

  def test_normalize_env_var
    ENV['RVIM_FS_VAR'] = '/tmp/x'
    assert_equal '/tmp/x/y', @editor.lua.eval('return vim.fs.normalize("$RVIM_FS_VAR/y")')
  ensure
    ENV.delete('RVIM_FS_VAR')
  end

  def test_normalize_collapses_slashes_and_strips_trailing
    assert_equal '/a/b', @editor.lua.eval('return vim.fs.normalize("/a//b/")')
    assert_equal '/',    @editor.lua.eval('return vim.fs.normalize("/")')
  end

  def test_find_downward
    File.write(File.join(@tmp, 'init.lua'), '')
    Dir.mkdir(File.join(@tmp, 'sub'))
    File.write(File.join(@tmp, 'sub', 'init.lua'), '')
    result = @editor.lua.eval(<<~LUA)
      local r = vim.fs.find("init.lua", { path = "#{@tmp}", limit = 10 })
      table.sort(r)
      return table.concat(r, ",")
    LUA
    expected = [File.join(@tmp, 'init.lua'), File.join(@tmp, 'sub', 'init.lua')].sort.join(',')
    assert_equal expected, result
  end

  def test_find_upward_locates_marker
    nested = File.join(@tmp, 'a', 'b', 'c')
    FileUtils.mkdir_p(nested)
    File.write(File.join(@tmp, 'a', '.git'), '')
    result = @editor.lua.eval(<<~LUA)
      local r = vim.fs.find(".git", { path = "#{nested}", upward = true, limit = 1 })
      return r[1]
    LUA
    assert_equal File.join(@tmp, 'a', '.git'), result
  end

  def test_find_respects_limit
    3.times { |i| File.write(File.join(@tmp, "f#{i}.txt"), '') }
    result = @editor.lua.eval(<<~LUA)
      local r = vim.fs.find(function(name) return name:match("^f") end,
                            { path = "#{@tmp}", limit = 2 })
      return #r
    LUA
    assert_equal 2, result.to_i
  end
end
