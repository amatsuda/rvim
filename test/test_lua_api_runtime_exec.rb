# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

# nvim_get_runtime_file, nvim_set_keymap (global), nvim_exec / nvim_exec2,
# nvim_exec_autocmds — the rest of lazy.nvim's must-haves.

class TestLuaApiRuntimeAndExec < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_list_runtime_paths_includes_user_runtimepath
    Dir.mktmpdir('rvim-rtp-') do |dir|
      @editor.settings.set(:runtimepath, "#{dir},/another")
      paths = @editor.lua.eval(<<~LUA)
        local r = vim.api.nvim_list_runtime_paths()
        return table.concat(r, ":")
      LUA
      assert_includes paths.split(':'), File.expand_path(dir)
    end
  end

  def test_get_runtime_file_returns_first_match
    Dir.mktmpdir('rvim-rtp-') do |dir|
      colors = File.join(dir, 'colors')
      Dir.mkdir(colors)
      File.write(File.join(colors, 'mine.lua'), '')
      @editor.settings.set(:runtimepath, dir)
      result = @editor.lua.eval(<<~LUA)
        local r = vim.api.nvim_get_runtime_file("colors/mine.lua", false)
        return r[1]
      LUA
      assert_equal File.join(dir, 'colors', 'mine.lua'), result
    end
  end

  def test_get_runtime_file_glob_with_all
    Dir.mktmpdir('rvim-rtp-') do |dir|
      Dir.mkdir(File.join(dir, 'colors'))
      File.write(File.join(dir, 'colors', 'a.lua'), '')
      File.write(File.join(dir, 'colors', 'b.lua'), '')
      @editor.settings.set(:runtimepath, dir)
      count = @editor.lua.eval(<<~LUA)
        return #vim.api.nvim_get_runtime_file("colors/*.lua", true)
      LUA
      assert_equal 2, count.to_i
    end
  end

  def test_set_keymap_global_registers
    @editor.lua.eval('vim.api.nvim_set_keymap("n", "gZ", ":echo 1<CR>", { noremap = true })')
    found = nil
    @editor.keymap.each(:normal) { |lhs, _| found = lhs if lhs == 'gZ' }
    assert_equal 'gZ', found
  end

  def test_set_keymap_global_with_callback_fires
    @editor.lua.eval(<<~LUA)
      hit = 0
      vim.api.nvim_set_keymap("n", "gQ", "", { callback = function() hit = hit + 1 end })
    LUA
    mapping = nil
    @editor.keymap.each(:normal) { |lhs, m| mapping = m if lhs == 'gQ' }
    refute_nil mapping
    refute_nil mapping.callback
    mapping.callback.call
    assert_equal 1, @editor.lua.eval('return hit').to_i
  end

  def test_del_keymap_removes
    @editor.lua.eval('vim.api.nvim_set_keymap("n", "gY", ":echo x<CR>", {})')
    found = false
    @editor.keymap.each(:normal) { |lhs, _| found = true if lhs == 'gY' }
    assert found, 'precondition: mapping should exist'

    @editor.lua.eval('vim.api.nvim_del_keymap("n", "gY")')
    still = false
    @editor.keymap.each(:normal) { |lhs, _| still = true if lhs == 'gY' }
    refute still, 'mapping should be deleted'
  end

  def test_exec_runs_multiple_lines
    seen = []
    @editor.define_singleton_method(:open) { |path| seen << path }
    @editor.lua.eval(<<~LUA)
      vim.api.nvim_exec("edit /tmp/aaa\\nedit /tmp/bbb", false)
    LUA
    assert_equal ['/tmp/aaa', '/tmp/bbb'], seen
  end

  def test_exec2_captures_output_when_requested
    # Any line that produces a status_message gets captured. An
    # unknown verb writes "E492: Not an editor command: ..." which
    # is sufficient to verify the capture sink is wired.
    out = @editor.lua.eval(<<~LUA)
      local r = vim.api.nvim_exec2("bogus_verb_xyz", { output = true })
      return r.output
    LUA
    assert_match(/E492/, out.to_s)
  end

  def test_exec2_without_output_returns_empty
    out = @editor.lua.eval(<<~LUA)
      local r = vim.api.nvim_exec2("bogus_verb_xyz", {})
      return r.output
    LUA
    assert_equal '', out
  end

  def test_exec_autocmds_fires_user_event
    @editor.lua.eval(<<~LUA)
      hits = 0
      vim.api.nvim_create_autocmd("User", {
        pattern = "LazyDone",
        callback = function() hits = hits + 1 end,
      })
      vim.api.nvim_exec_autocmds("User", { pattern = "LazyDone" })
    LUA
    assert_equal 1, @editor.lua.eval('return hits').to_i
  end

  def test_exec_autocmds_glob_pattern_matches
    @editor.lua.eval(<<~LUA)
      hits = 0
      vim.api.nvim_create_autocmd("User", {
        pattern = "Lazy*",
        callback = function() hits = hits + 1 end,
      })
      vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad" })
      vim.api.nvim_exec_autocmds("User", { pattern = "LazyDone" })
    LUA
    assert_equal 2, @editor.lua.eval('return hits').to_i
  end
end
