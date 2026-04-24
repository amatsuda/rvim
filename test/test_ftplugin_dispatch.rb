# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestFtpluginDispatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @tmp = Dir.mktmpdir('rvim-ft')
    @editor.settings.set(:runtimepath, @tmp)
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
  end

  def test_load_filetype_scripts_sources_ftplugin
    FileUtils.mkdir_p(File.join(@tmp, 'ftplugin'))
    File.write(File.join(@tmp, 'ftplugin', 'ruby.vim'), ":let from_ftplugin = 1\n")
    @editor.load_filetype_scripts(:ruby)
    assert_equal '1', @editor.let_vars['from_ftplugin']
  end

  def test_load_filetype_scripts_sources_indent
    FileUtils.mkdir_p(File.join(@tmp, 'indent'))
    File.write(File.join(@tmp, 'indent', 'python.vim'), ":let from_indent = 1\n")
    @editor.load_filetype_scripts(:python)
    assert_equal '1', @editor.let_vars['from_indent']
  end

  def test_load_filetype_scripts_sources_syntax
    FileUtils.mkdir_p(File.join(@tmp, 'syntax'))
    File.write(File.join(@tmp, 'syntax', 'yaml.vim'), ":let from_syntax = 1\n")
    @editor.load_filetype_scripts(:yaml)
    assert_equal '1', @editor.let_vars['from_syntax']
  end

  def test_missing_filetype_files_are_skipped_silently
    @editor.load_filetype_scripts(:nonexistent)
    assert_nil @editor.let_vars['from_ftplugin']
  end

  def test_nil_filetype_is_a_noop
    assert_nothing_raised { @editor.load_filetype_scripts(nil) }
  end
end
