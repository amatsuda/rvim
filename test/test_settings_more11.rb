# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestTildeop < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def test_default_off_toggles_single_char
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:rvim_tilde, nil)
    assert_equal 'Hello', @editor.buffer_of_lines[0]
    assert_equal 1, @editor.byte_pointer
  end

  def test_tildeop_on_makes_tilde_an_operator
    @editor.settings.set(:tildeop, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello WORLD'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:rvim_tilde, nil)
    # tildeop sets pending; next key is the motion
    @editor.update(k('$'))
    assert_equal 'HELLO world', @editor.buffer_of_lines[0]
  end

  def test_top_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set top'))
    assert_equal true, @editor.settings.get(:tildeop)
  end
end

class TestWritebackup < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:writebackup)
  end

  def test_writebackup_creates_and_removes_after_save
    f = Tempfile.new(['wb', '.txt'])
    f.binmode; f.write("orig\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.settings.set(:backup, false)
    @editor.settings.set(:writebackup, true)
    @editor.save
    backup = "#{f.path}~"
    refute File.exist?(backup), 'transient writebackup should be removed after success'
    assert_match(/changed/, File.read(f.path))
  ensure
    f&.unlink
    File.delete("#{f.path}~") if f && File.exist?("#{f.path}~")
  end

  def test_backup_on_keeps_file_even_with_writebackup
    f = Tempfile.new(['wb', '.txt'])
    f.binmode; f.write("orig\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.settings.set(:backup, true)
    @editor.settings.set(:writebackup, true)
    @editor.save
    assert File.exist?("#{f.path}~"), 'backup=true keeps the file'
  ensure
    f&.unlink
    File.delete("#{f.path}~") if f && File.exist?("#{f.path}~")
  end

  def test_no_backup_when_both_off
    f = Tempfile.new(['wb', '.txt'])
    f.binmode; f.write("orig\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.settings.set(:backup, false)
    @editor.settings.set(:writebackup, false)
    @editor.save
    refute File.exist?("#{f.path}~")
  ensure
    f&.unlink
  end

  def test_wb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nowb'))
    assert_equal false, @editor.settings.get(:writebackup)
  end
end

class TestShellSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_bin_sh
    assert_equal '/bin/sh', @editor.settings.get(:shell)
  end

  def test_filter_run_uses_default_shell
    out = Rvim::Filter.run('echo hi')
    assert_equal "hi\n", out.stdout
  end

  def test_filter_run_with_custom_shell
    # Use a shell that's definitely on the system
    out = Rvim::Filter.run('echo hello', shell: '/bin/sh')
    assert_equal "hello\n", out.stdout
  end

  def test_filter_command_uses_settings_shell
    @editor.settings.set(:shell, '/bin/sh')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!echo from_setting'))
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/from_setting/, body)
  end

  def test_sh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sh=/bin/bash'))
    assert_equal '/bin/bash', @editor.settings.get(:shell)
  end
end
