# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

# vim.loop.fs_* — sync filesystem ops. lazy.nvim uses these to walk
# plugin checkouts (fs_scandir, fs_stat) and write its lockfile
# (fs_open + fs_write + fs_close).
class TestLuaLoopFs < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    @tmp = Dir.mktmpdir('rvim-fs-')
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.exist?(@tmp)
  end

  def test_fs_stat_returns_table_for_existing_file
    path = File.join(@tmp, 'a.txt')
    File.write(path, 'hello')
    res = @editor.lua.eval(<<~LUA)
      local s = vim.loop.fs_stat("#{path}")
      return s.type .. ":" .. s.size
    LUA
    assert_equal 'file:5', res
  end

  def test_fs_stat_returns_nil_for_missing
    res = @editor.lua.eval(<<~LUA)
      local s = vim.loop.fs_stat("#{@tmp}/nope")
      if s == nil then return "nil" else return "table" end
    LUA
    assert_equal 'nil', res
  end

  def test_fs_stat_directory_type
    res = @editor.lua.eval(%(return vim.loop.fs_stat("#{@tmp}").type))
    assert_equal 'directory', res
  end

  def test_fs_lstat_distinguishes_symlink
    target = File.join(@tmp, 'real.txt')
    link   = File.join(@tmp, 'link')
    File.write(target, 'x')
    File.symlink(target, link)
    res = @editor.lua.eval(<<~LUA)
      return vim.loop.fs_lstat("#{link}").type
    LUA
    assert_equal 'link', res
  end

  def test_fs_mkdir_and_rmdir
    sub = File.join(@tmp, 'sub')
    @editor.lua.eval(%(vim.loop.fs_mkdir("#{sub}", 493)))
    assert File.directory?(sub)
    @editor.lua.eval(%(vim.loop.fs_rmdir("#{sub}")))
    refute File.exist?(sub)
  end

  def test_fs_unlink_removes_file
    path = File.join(@tmp, 'a.txt')
    File.write(path, 'x')
    @editor.lua.eval(%(vim.loop.fs_unlink("#{path}")))
    refute File.exist?(path)
  end

  def test_fs_rename
    src = File.join(@tmp, 'old')
    dst = File.join(@tmp, 'new')
    File.write(src, 'x')
    @editor.lua.eval(%(vim.loop.fs_rename("#{src}", "#{dst}")))
    refute File.exist?(src)
    assert File.exist?(dst)
  end

  def test_fs_copyfile
    src = File.join(@tmp, 'src')
    dst = File.join(@tmp, 'dst')
    File.write(src, 'payload')
    @editor.lua.eval(%(vim.loop.fs_copyfile("#{src}", "#{dst}")))
    assert_equal 'payload', File.read(dst)
  end

  def test_fs_access
    path = File.join(@tmp, 'a')
    File.write(path, 'x')
    assert_equal true, @editor.lua.eval(%(return vim.loop.fs_access("#{path}", "R")))
    assert_equal false, @editor.lua.eval(%(return vim.loop.fs_access("#{@tmp}/missing", "R")))
  end

  def test_fs_realpath_resolves_symlinks
    real = File.join(@tmp, 'real.txt')
    link = File.join(@tmp, 'link')
    File.write(real, 'x')
    File.symlink(real, link)
    resolved = @editor.lua.eval(%(return vim.loop.fs_realpath("#{link}")))
    assert_equal File.realpath(real), resolved
  end

  def test_fs_scandir_walks_entries
    File.write(File.join(@tmp, 'a'), '')
    File.write(File.join(@tmp, 'b'), '')
    Dir.mkdir(File.join(@tmp, 'c'))
    names = @editor.lua.eval(<<~LUA)
      local h = vim.loop.fs_scandir("#{@tmp}")
      local out = {}
      while true do
        local name, type = vim.loop.fs_scandir_next(h)
        if name == nil then break end
        table.insert(out, name .. ":" .. type)
      end
      table.sort(out)
      return table.concat(out, ",")
    LUA
    assert_equal 'a:file,b:file,c:directory', names
  end

  def test_fs_open_write_read_close_roundtrip
    path = File.join(@tmp, 'rt.txt')
    out = @editor.lua.eval(<<~LUA)
      local fd = vim.loop.fs_open("#{path}", "w", 420)
      vim.loop.fs_write(fd, "hello world", 0)
      vim.loop.fs_close(fd)
      local fd2 = vim.loop.fs_open("#{path}", "r", 420)
      local data = vim.loop.fs_read(fd2, 64, 0)
      vim.loop.fs_close(fd2)
      return data
    LUA
    assert_equal 'hello world', out
  end

  def test_cwd_matches_dir_pwd
    assert_equal Dir.pwd, @editor.lua.eval('return vim.loop.cwd()')
  end

  def test_os_homedir
    assert_equal Dir.home, @editor.lua.eval('return vim.loop.os_homedir()')
  end

  def test_os_uname_table
    res = @editor.lua.eval(<<~LUA)
      local u = vim.loop.os_uname()
      return (u.sysname or "") .. "/" .. (u.machine or "")
    LUA
    assert_match(%r{\w+/\w+}, res)
  end

  def test_os_getenv
    ENV['RVIM_FS_TEST'] = 'yes'
    assert_equal 'yes', @editor.lua.eval('return vim.loop.os_getenv("RVIM_FS_TEST")')
  ensure
    ENV.delete('RVIM_FS_TEST')
  end

  def test_getpid_matches_process_pid
    assert_equal Process.pid, @editor.lua.eval('return vim.loop.getpid()').to_i
  end
end
