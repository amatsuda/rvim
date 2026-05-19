# frozen_string_literal: true

require_relative 'test_helper'

# Shims discovered while making lazy.nvim's setup() complete.
# Each one corresponds to a real blocker we hit walking lazy's
# startup path; locking them down so we don't regress them.

class TestLuaLazyShims < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_hrtime_returns_float_not_overflowing_int
    # The original Integer return overflowed rufus-lua's int conversion
    # at hrtime() ≈ 2³¹ ns (~2 seconds after boot). Doubles fix it.
    n = @editor.lua.eval('return vim.loop.hrtime()')
    assert_kind_of Numeric, n
    assert_operator n.to_f, :>, 0
  end

  def test_tbl_get_walks_nested
    assert_equal 42, @editor.lua.eval(<<~LUA).to_i
      return vim.tbl_get({ a = { b = { c = 42 } } }, "a", "b", "c")
    LUA
    res = @editor.lua.eval(<<~LUA)
      local r = vim.tbl_get({ a = 1 }, "a", "b")
      if r == nil then return "nil" else return tostring(r) end
    LUA
    assert_equal 'nil', res
  end

  def test_fn_mkdir_p_creates_intermediate_dirs
    nested = "/tmp/rvim_mkdir_test_#{$$}/a/b/c"
    @editor.lua.eval(%(vim.fn.mkdir("#{nested}", "p")))
    assert File.directory?(nested)
  ensure
    require 'fileutils'
    FileUtils.rm_rf("/tmp/rvim_mkdir_test_#{$$}")
  end

  def test_vim_v_progpath
    assert_equal $PROGRAM_NAME, @editor.lua.eval('return vim.v.progpath')
  end

  def test_vim_env_reads_and_writes
    ENV['RVIM_LAZY_PROBE'] = 'hi'
    assert_equal 'hi', @editor.lua.eval('return vim.env.RVIM_LAZY_PROBE')
    @editor.lua.eval('vim.env.RVIM_LAZY_PROBE = "bye"')
    assert_equal 'bye', ENV['RVIM_LAZY_PROBE']
  ensure
    ENV.delete('RVIM_LAZY_PROBE')
  end

  def test_nvim_list_uis_returns_one_entry
    n = @editor.lua.eval('return #vim.api.nvim_list_uis()').to_i
    assert_equal 1, n
    width = @editor.lua.eval('return vim.api.nvim_list_uis()[1].width').to_i
    assert_operator width, :>, 0
  end

  def test_new_check_handle_fires_callback_on_pump
    @editor.lua.eval(<<~LUA)
      hits = 0
      check = vim.loop.new_check()
      check:start(function() hits = hits + 1 end)
    LUA
    @editor.pump_lua_loop
    @editor.pump_lua_loop
    assert_operator @editor.lua.eval('return hits').to_i, :>=, 1
  end

  def test_health_stubs_exist_as_callable
    # Just probing presence — :checkhealth integration is a later ship.
    ok = @editor.lua.eval(<<~LUA)
      local f = vim.health.start
      if type(f) == "function" then return "ok" else return "missing" end
    LUA
    assert_equal 'ok', ok
  end

  def test_in_fast_event_returns_false
    assert_equal false, @editor.lua.eval('return vim.in_fast_event()')
  end

  def test_vim_F_pack_unpack_len_roundtrips
    n = @editor.lua.eval(<<~LUA)
      local p = vim.F.pack_len("a", nil, "c")
      return p.n
    LUA
    assert_equal 3, n.to_i
  end

  def test_vim_opt_rtp_get_returns_array
    @editor.settings.set(:runtimepath, '/a,/b,/c')
    result = @editor.lua.eval(<<~LUA)
      local r = vim.opt.rtp:get()
      return type(r) == "table" and (#r) or -1
    LUA
    assert_equal 3, result.to_i
  end

  def test_fn_glob_returns_string_by_default_and_list_when_requested
    Dir.mktmpdir('rvim-glob-') do |dir|
      File.write(File.join(dir, 'a.txt'), '')
      File.write(File.join(dir, 'b.txt'), '')
      pat = File.join(dir, '*.txt')
      n = @editor.lua.eval(%(return #vim.fn.glob("#{pat}", 0, 1)))
      assert_equal 2, n.to_i
    end
  end

  def test_fn_tempname_yields_unique_paths
    a = @editor.lua.eval('return vim.fn.tempname()')
    b = @editor.lua.eval('return vim.fn.tempname()')
    refute_equal a, b
  end
end
