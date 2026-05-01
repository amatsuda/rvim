# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

# Regression: ~/.config/rvim/lua/<mod>.lua should be require()-able from
# init.lua. The fix prepends the user config dir to &runtimepath at startup
# (matching NeoVim) and re-syncs package.path on any later runtimepath edit.
class TestLuaUserRuntimepath < Test::Unit::TestCase
  def setup
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    @home = Dir.mktmpdir('rvim-rtp-user')
    @real_xdg = ENV['XDG_CONFIG_HOME']
    ENV['XDG_CONFIG_HOME'] = @home
  end

  def teardown
    if @real_xdg
      ENV['XDG_CONFIG_HOME'] = @real_xdg
    else
      ENV.delete('XDG_CONFIG_HOME')
    end
    FileUtils.remove_entry(@home) if @home && File.directory?(@home)
  end

  def test_user_config_dir_is_prepended_to_runtimepath
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_user_runtimepath(editor)
    rtp = editor.settings.get(:runtimepath).to_s.split(',')
    assert_equal File.join(@home, 'rvim'), rtp.first
    assert_includes rtp, File.join(@home, 'rvim', 'after')
  end

  def test_require_resolves_for_user_config_lua_modules
    FileUtils.mkdir_p(File.join(@home, 'rvim', 'lua'))
    File.write(File.join(@home, 'rvim', 'lua', 'keymap.lua'),
               'return { ok = true }')
    File.write(File.join(@home, 'rvim', 'init.lua'),
               'vim.g.from_keymap = require("keymap").ok')

    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_user_runtimepath(editor)
    editor.source(Rvim::Editor.init_lua_path)

    assert_equal true, editor.let_vars['from_keymap']
  end

  def test_runtimepath_edit_at_runtime_refreshes_package_path
    extra = File.join(@home, 'extra')
    FileUtils.mkdir_p(File.join(extra, 'lua'))
    File.write(File.join(extra, 'lua', 'late.lua'), 'return "appended"')

    editor = Rvim::Editor.new(Reline.core.config)
    # Trigger the runtime to install once (so a later refresh has somewhere to
    # write package.path).
    editor.lua.eval('return 1')

    # Simulate vim.opt.rtp:prepend(extra) by setting via the settings API.
    rtp = editor.settings.get(:runtimepath).to_s
    editor.settings.set(:runtimepath, "#{extra},#{rtp}")

    result = editor.lua.eval('return require("late")')
    assert_equal 'appended', result
  end

  def test_user_after_dir_is_appended
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_user_runtimepath(editor)
    rtp = editor.settings.get(:runtimepath).to_s.split(',')
    assert_equal File.join(@home, 'rvim', 'after'), rtp.last
  end
end
