# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

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

  def test_jit_table_present
    # rufus-lua ships LuaJIT here, but in case it doesn't, our shim
    # provides jit.version. Either way the probe lazy.nvim makes
    # (`jit and jit.version`) succeeds.
    refute_nil @editor.lua.eval('return jit and jit.version'),
               'expected jit.version to be set'
  end

  def test_ffi_available_via_pcall_require
    ok = @editor.lua.eval(<<~LUA)
      local r, mod = pcall(require, "ffi")
      return (r and type(mod) == "table") and "ok" or "fail"
    LUA
    assert_equal 'ok', ok
  end

  def test_vim_cmd_dotted_form
    seen = []
    @editor.define_singleton_method(:open) { |path| seen << path }
    @editor.lua.eval('vim.cmd.edit("/tmp/dotted")')
    assert_equal ['/tmp/dotted'], seen
  end

  def test_vim_cmd_call_form_still_works
    seen = []
    @editor.define_singleton_method(:open) { |path| seen << path }
    @editor.lua.eval('vim.cmd("edit /tmp/calling")')
    assert_equal ['/tmp/calling'], seen
  end

  def test_vim_cmd_structured_form
    seen = []
    @editor.define_singleton_method(:open) { |path| seen << path }
    @editor.lua.eval('vim.cmd({ cmd = "edit", args = { "/tmp/struct" } })')
    assert_equal ['/tmp/struct'], seen
  end

  def test_vim_schedule_wrap_defers_to_main_thread
    @editor.lua.eval(<<~LUA)
      hit = 0
      cb = vim.schedule_wrap(function(v) hit = v end)
      cb(42)
    LUA
    # Before pump, the wrapped callback hasn't fired.
    assert_equal 0, @editor.lua.eval('return hit').to_i
    @editor.pump_lua_loop
    assert_equal 42, @editor.lua.eval('return hit').to_i
  end

  def test_fn_getcompletion_color_finds_bundled
    Rvim::Editor.ensure_bundled_runtime(@editor)
    list = @editor.lua.eval(<<~LUA)
      local r = vim.fn.getcompletion("", "color")
      return table.concat(r, ",")
    LUA
    assert_includes list.split(','), 'default'
  end

  def test_fn_system_argv_list_form
    # lazy.nvim's bootstrap calls vim.fn.system({...}) with a list to
    # avoid shell quoting. Both forms must work.
    out = @editor.lua.eval('return vim.fn.system({"echo", "hello world"})')
    assert_equal "hello world\n", out
  end

  def test_fn_system_sets_v_shell_error_on_success
    @editor.lua.eval('vim.fn.system({"true"})')
    assert_equal 0, @editor.lua.eval('return vim.v.shell_error').to_i
  end

  def test_fn_system_sets_v_shell_error_on_failure
    @editor.lua.eval('vim.fn.system({"false"})')
    assert_equal 1, @editor.lua.eval('return vim.v.shell_error').to_i
  end

  def test_fn_system_string_form_still_works
    out = @editor.lua.eval(%(return vim.fn.system("echo hi")))
    assert_match(/hi/, out.to_s)
  end

  def test_vim_g_table_value_round_trips
    # Storing a Lua table in vim.g and reading it back used to crash
    # with "don't know how to pass Ruby instance of Rufus::Lua::Table"
    # because the stored Rufus::Lua::Table couldn't be re-pushed.
    n = @editor.lua.eval(<<~LUA)
      vim.g.my_arr = { 10, 20, 30 }
      local got = vim.g.my_arr
      return got[1] + got[2] + got[3]
    LUA
    assert_equal 60, n.to_i
  end

  def test_vim_opt_rtp_assignment_from_array_joins_to_comma_string
    @editor.lua.eval('vim.opt.rtp = { "/a", "/b", "/c" }')
    assert_equal '/a,/b,/c', @editor.settings.get(:runtimepath)
  end

  def test_vim_opt_rtp_round_trips_through_get_set_get
    @editor.lua.eval(<<~LUA)
      local r = vim.opt.rtp:get()
      table.insert(r, "/extra")
      vim.opt.rtp = r
    LUA
    assert_includes @editor.settings.get(:runtimepath).to_s.split(','), '/extra'
  end

  def test_vim_loader_find_locates_module_under_lua_dir
    Dir.mktmpdir('rvim-loader-') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'lua', 'pkg'))
      File.write(File.join(dir, 'lua', 'pkg.lua'), '-- top-level')
      File.write(File.join(dir, 'lua', 'pkg', 'sub.lua'), '-- nested')
      result = @editor.lua.eval(<<~LUA)
        local r = vim.loader.find("pkg.sub", { rtp = false, paths = { "#{dir}" } })
        return r[1] and r[1].modpath
      LUA
      assert_equal File.join(dir, 'lua', 'pkg', 'sub.lua'), result
    end
  end

  def test_vim_o_reads_and_writes_options
    @editor.lua.eval('vim.o.tabstop = 8')
    assert_equal 8, @editor.settings.get(:tabstop)
    assert_equal 8, @editor.lua.eval('return vim.o.tabstop').to_i
  end

  def test_nvim_get_keymap_lists_normal_mode_entries
    @editor.lua.eval('vim.keymap.set("n", "<leader>x", function() end, { desc = "test" })')
    @editor.let_vars['mapleader'] = ' '
    count = @editor.lua.eval('return #vim.api.nvim_get_keymap("n")').to_i
    assert_operator count, :>, 0
    sample = @editor.lua.eval(<<~LUA)
      local m = vim.api.nvim_get_keymap("n")
      for _, e in ipairs(m) do
        if e.lhs:find("x", 1, true) then return e.lhs end
      end
      return ""
    LUA
    refute_empty sample
  end

  def test_nvim_get_autocmds_filtered_by_event
    @editor.lua.eval(<<~LUA)
      vim.api.nvim_create_autocmd("BufEnter", { pattern = "*", command = "echo hi" })
      vim.api.nvim_create_autocmd("BufLeave", { pattern = "*.txt", command = "echo bye" })
    LUA
    n = @editor.lua.eval('return #vim.api.nvim_get_autocmds({ event = "BufEnter" })').to_i
    assert_equal 1, n
  end

  def test_nvim_create_user_command_does_not_leak_struct_to_lua
    # Regression: the previous impl returned the assigned UserCommand
    # struct, which rufus-lua couldn't push back, breaking any caller
    # that used the return value (lazy.nvim's autocmd dispatch did).
    assert_nothing_raised do
      @editor.lua.eval('vim.api.nvim_create_user_command("MyCmd", "echo hi", {})')
    end
    assert_equal nil, @editor.lua.eval('return vim.api.nvim_create_user_command("MyCmd2", "echo bye", {})')
  end

  def test_vim_loader_find_wildcard_returns_all_modules
    Dir.mktmpdir('rvim-loader-') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'lua', 'pkg'))
      File.write(File.join(dir, 'lua', 'pkg', 'a.lua'), '')
      File.write(File.join(dir, 'lua', 'pkg', 'b.lua'), '')
      count = @editor.lua.eval(<<~LUA)
        return #vim.loader.find("*", { all = true, rtp = false, paths = { "#{dir}" } })
      LUA
      assert_equal 2, count.to_i
    end
  end
end
