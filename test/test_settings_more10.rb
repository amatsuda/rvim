# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'tmpdir'
require 'fileutils'

class TestBackupExtAndDir < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:backup, true)
  end

  def test_default_extension_tilde
    assert_equal '~', @editor.settings.get(:backupext)
  end

  def test_default_dir_dot
    assert_equal '.', @editor.settings.get(:backupdir)
  end

  def test_custom_backupext
    f = Tempfile.new(['bex', '.txt'])
    f.binmode; f.write("orig\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.settings.set(:backupext, '.bak')
    @editor.save
    backup = "#{f.path}.bak"
    assert File.exist?(backup), "expected backup at #{backup}"
    assert_equal "orig\n", File.binread(backup)
  ensure
    f&.unlink
    File.delete("#{f.path}.bak") if f && File.exist?("#{f.path}.bak")
  end

  def test_custom_backupdir
    Dir.mktmpdir do |target_dir|
      Dir.mktmpdir do |src_dir|
        src = File.join(src_dir, 'foo.txt')
        File.binwrite(src, "orig\n")
        @editor.open(src)
        @editor.buffer_of_lines[0] = +'changed'
        @editor.settings.set(:backupdir, target_dir)
        @editor.save
        backup_at_dir = File.join(target_dir, 'foo.txt~')
        assert File.exist?(backup_at_dir), "expected backup at #{backup_at_dir}"
      end
    end
  end

  def test_bex_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set bex=.orig'))
    assert_equal '.orig', @editor.settings.get(:backupext)
  end

  def test_bdir_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set bdir=/tmp/backups'))
    assert_equal '/tmp/backups', @editor.settings.get(:backupdir)
  end
end

class TestShowbreak < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:showbreak)
  end

  def test_sbr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sbr=>>'))
    assert_equal '>>', @editor.settings.get(:showbreak)
  end

  def test_renders_at_continuation
    @editor.settings.set(:showbreak, '↪ ')
    @editor.settings.set(:wrap, true)
    long = 'A' * 30
    @editor.instance_variable_set(:@buffer_of_lines, [long])
    buf = Rvim::Buffer.new(1, nil); buf.lines = [long]
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf); win.row = 0; win.col = 0; win.width = 12; win.height = 5
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)

    out = @screen.send(:render_window, win)
    # Continuation segments should include the showbreak marker
    assert_match(/↪ /, out)
  end

  def test_no_marker_on_first_segment
    @editor.settings.set(:showbreak, '>>>')
    @editor.settings.set(:wrap, true)
    @editor.instance_variable_set(:@buffer_of_lines, ['short'])
    buf = Rvim::Buffer.new(1, nil); buf.lines = ['short']
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf); win.row = 0; win.col = 0; win.width = 80; win.height = 5
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)

    out = @screen.send(:render_window, win)
    refute_match(/>>>/, out)
  end
end
