# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestRuntimeCommand < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @tmp = Dir.mktmpdir('rvim-rtp')
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
  end

  def test_runtime_finds_first_match
    FileUtils.mkdir_p(File.join(@tmp, 'plugin'))
    plugin = File.join(@tmp, 'plugin', 'foo.vim')
    File.write(plugin, ":let tested = 1\n")
    @editor.settings.set(:runtimepath, @tmp)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':runtime plugin/foo.vim'))
    assert_equal '1', @editor.let_vars['tested']
  end

  def test_runtime_glob_matches_multiple_with_bang
    FileUtils.mkdir_p(File.join(@tmp, 'plugin'))
    File.write(File.join(@tmp, 'plugin', 'a.vim'), ":let a_var = 1\n")
    File.write(File.join(@tmp, 'plugin', 'b.vim'), ":let b_var = 1\n")
    @editor.settings.set(:runtimepath, @tmp)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':runtime! plugin/*.vim'))
    assert_equal '1', @editor.let_vars['a_var']
    assert_equal '1', @editor.let_vars['b_var']
  end

  def test_runtime_no_match_sets_error
    @editor.settings.set(:runtimepath, @tmp)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':runtime missing.vim'))
    assert_match(/E484/, @editor.status_message.to_s)
  end

  def test_runtime_no_arg_sets_error
    Rvim::Command.execute(@editor, Rvim::Command.parse(':runtime'))
    assert_match(/E471/, @editor.status_message.to_s)
  end
end

class TestPackaddCommand < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @home_dir = Dir.mktmpdir('rvim-home')
    @real_home = ENV['HOME']
    ENV['HOME'] = @home_dir
  end

  def teardown
    ENV['HOME'] = @real_home
    FileUtils.remove_entry(@home_dir) if @home_dir && File.directory?(@home_dir)
  end

  def test_packadd_appends_to_runtimepath
    pkg_dir = File.join(@home_dir, '.vim', 'pack', 'mine', 'start', 'mypkg')
    FileUtils.mkdir_p(File.join(pkg_dir, 'plugin'))
    File.write(File.join(pkg_dir, 'plugin', 'load.vim'), ":let loaded = 1\n")
    Rvim::Command.execute(@editor, Rvim::Command.parse(':packadd mypkg'))
    assert_includes @editor.settings.get(:runtimepath).split(','), pkg_dir
    assert_equal '1', @editor.let_vars['loaded']
  end

  def test_packadd_bang_skips_plugin_sourcing
    pkg_dir = File.join(@home_dir, '.vim', 'pack', 'mine', 'opt', 'optpkg')
    FileUtils.mkdir_p(File.join(pkg_dir, 'plugin'))
    File.write(File.join(pkg_dir, 'plugin', 'load.vim'), ":let notloaded = 1\n")
    Rvim::Command.execute(@editor, Rvim::Command.parse(':packadd! optpkg'))
    assert_includes @editor.settings.get(:runtimepath).split(','), pkg_dir
    assert_nil @editor.let_vars['notloaded']
  end

  def test_packadd_unknown_pkg_errors
    Rvim::Command.execute(@editor, Rvim::Command.parse(':packadd nonexistent'))
    assert_match(/E919/, @editor.status_message.to_s)
  end
end
