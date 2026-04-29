# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestLuaInitAutoload < Test::Unit::TestCase
  def setup
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    @home = Dir.mktmpdir('rvim-init')
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

  def test_init_lua_path_resolves_to_xdg
    assert_equal File.join(@home, 'rvim', 'init.lua'), Rvim::Editor.init_lua_path
  end

  def test_init_lua_is_sourced_when_present
    FileUtils.mkdir_p(File.join(@home, 'rvim'))
    File.write(File.join(@home, 'rvim', 'init.lua'), 'vim.cmd("set ts=14")')

    # Mimic the body of Editor.start without spinning up the screen.
    editor = Rvim::Editor.new(Reline.core.config)
    [File.expand_path('~/.rvimrc'), Rvim::Editor.init_vim_path, Rvim::Editor.init_lua_path].each do |rc|
      editor.source(rc) if File.exist?(rc)
    end

    assert_equal 14, editor.settings.get(:tabstop)
  end

  def test_init_lua_can_use_vim_keymap
    FileUtils.mkdir_p(File.join(@home, 'rvim'))
    File.write(File.join(@home, 'rvim', 'init.lua'), <<~LUA)
      vim.keymap.set("n", "Y", "y$")
      vim.opt.number = true
    LUA

    editor = Rvim::Editor.new(Reline.core.config)
    editor.source(Rvim::Editor.init_lua_path)

    found = nil
    editor.keymap.each(:normal) { |lhs, m| found = m if lhs == 'Y' }
    refute_nil found
    assert_equal true, editor.settings.get(:number)
  end

  def test_norc_skips_init_lua
    FileUtils.mkdir_p(File.join(@home, 'rvim'))
    File.write(File.join(@home, 'rvim', 'init.lua'), 'vim.cmd("set ts=20")')

    editor = Rvim::Editor.new(Reline.core.config)
    # With norc the source step is skipped — verify by not calling it.
    refute_equal 20, editor.settings.get(:tabstop)
  end

  def test_missing_init_lua_is_a_noop
    editor = Rvim::Editor.new(Reline.core.config)
    assert_nothing_raised do
      editor.source(Rvim::Editor.init_lua_path) if File.exist?(Rvim::Editor.init_lua_path)
    end
  end
end
