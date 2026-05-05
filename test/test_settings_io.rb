# frozen_string_literal: true

require_relative 'test_helper'

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

class TestAutoread < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:autoread)
  end

  def test_ar_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ar'))
    assert_equal true, @editor.settings.get(:autoread)
  end

  def test_buffer_tracks_mtime_on_load
    f = Tempfile.new(['ar', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    refute_nil @editor.current_buffer.mtime
  ensure
    f&.unlink
  end

  def test_external_change_detected
    f = Tempfile.new(['ar', '.txt'])
    f.binmode; f.write("first\n"); f.close
    @editor.open(f.path)
    sleep 1.1 # mtime resolution
    File.binwrite(f.path, "external change\n")
    assert @editor.current_buffer.file_changed_externally?
  ensure
    f&.unlink
  end

  def test_autoread_reloads_on_swap
    f1 = Tempfile.new(['ar1', '.txt'])
    f2 = Tempfile.new(['ar2', '.txt'])
    f1.binmode; f1.write("a1\n"); f1.close
    f2.binmode; f2.write("b1\n"); f2.close
    @editor.open(f1.path)
    @editor.open(f2.path)

    # Modify f1 externally
    sleep 1.1
    File.binwrite(f1.path, "a-updated\n")

    @editor.settings.set(:autoread, true)
    @editor.swap_to_buffer(@editor.buffers.values.find { |b| b.filepath == f1.path })
    assert_equal 'a-updated', @editor.buffer_of_lines[0]
  ensure
    f1&.unlink
    f2&.unlink
  end

  def test_autoread_off_no_reload
    f = Tempfile.new(['ar', '.txt'])
    f.binmode; f.write("first\n"); f.close
    @editor.open(f.path)
    @editor.open(f.path) # creates a second buffer is the same; let me make 2
    f2 = Tempfile.new(['ar2', '.txt'])
    f2.binmode; f2.write("second\n"); f2.close
    @editor.open(f2.path)

    sleep 1.1
    File.binwrite(f.path, "external\n")

    @editor.settings.set(:autoread, false)
    @editor.swap_to_buffer(@editor.buffers.values.find { |b| b.filepath == f.path })
    assert_equal 'first', @editor.buffer_of_lines[0]
  ensure
    f&.unlink
    f2&.unlink
  end
end

class TestHiddenSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:hidden)
  end

  def test_hid_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nohid'))
    assert_equal false, @editor.settings.get(:hidden)
  end

  def test_no_hidden_blocks_modified_buffer_swap
    Tempfile.open(['h1', '.txt']) do |f|
      Tempfile.open(['h2', '.txt']) do |g|
        f.binmode; f.write("first\n"); f.close
        g.binmode; g.write("second\n"); g.close
        @editor.open(f.path)
        @editor.open(g.path)
        @editor.swap_to_buffer(@editor.buffers.values.find { |b| b.filepath == f.path })
        @editor.modified = true
        @editor.settings.set(:hidden, false)
        before = @editor.filepath
        @editor.cycle_buffer(+1)
        # Cycle blocked → still on the modified buffer
        assert_equal before, @editor.filepath
        assert_match(/E37/, @editor.status_message.to_s)
      end
    end
  end

  def test_hidden_on_allows_swap_with_modified_buffer
    Tempfile.open(['h1', '.txt']) do |f|
      Tempfile.open(['h2', '.txt']) do |g|
        f.binmode; f.write("first\n"); f.close
        g.binmode; g.write("second\n"); g.close
        @editor.open(f.path)
        @editor.open(g.path)
        @editor.swap_to_buffer(@editor.buffers.values.find { |b| b.filepath == f.path })
        @editor.modified = true
        @editor.settings.set(:hidden, true)
        @editor.cycle_buffer(+1)
        refute_equal f.path, @editor.filepath
      end
    end
  end
end

class TestUndolevelsSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_1000
    assert_equal 1000, @editor.settings.get(:undolevels)
  end

  def test_ul_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ul=50'))
    assert_equal 50, @editor.settings.get(:undolevels)
  end

  def test_cap_undo_history_trims
    f = Tempfile.new(['ul', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    @editor.settings.set(:undolevels, 3)
    # Stuff a deeper history
    @editor.instance_variable_set(:@undo_redo_history, (0..9).map { |i| [["v#{i}"], 0, 0] })
    @editor.instance_variable_set(:@undo_redo_index, 9)
    @editor.send(:cap_undo_history)
    assert_equal 3, @editor.instance_variable_get(:@undo_redo_history).size
    # Index also bumped down by what was dropped (7 entries dropped)
    assert_equal 2, @editor.instance_variable_get(:@undo_redo_index)
  ensure
    f&.unlink
  end
end

class TestEndofline < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:endofline)
  end

  def test_eol_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set noeol'))
    assert_equal false, @editor.settings.get(:endofline)
  end

  def test_save_writes_trailing_newline_when_on
    f = Tempfile.new(['eol', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.save
    bytes = File.binread(f.path)
    assert_equal "changed\n", bytes
  ensure
    f&.unlink
  end

  def test_save_no_trailing_newline_when_both_off
    f = Tempfile.new(['eol', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.settings.set(:endofline, false)
    @editor.settings.set(:fixendofline, false)
    @editor.save
    bytes = File.binread(f.path)
    assert_equal 'changed', bytes
  ensure
    f&.unlink
  end

  def test_fixendofline_forces_trailing_newline
    f = Tempfile.new(['eol', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.settings.set(:endofline, false)
    @editor.settings.set(:fixendofline, true)
    @editor.save
    bytes = File.binread(f.path)
    assert_equal "changed\n", bytes
  ensure
    f&.unlink
  end
end

class TestFixendofline < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:fixendofline)
  end

  def test_fixeol_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nofixeol'))
    assert_equal false, @editor.settings.get(:fixendofline)
  end
end

class TestSwitchbufStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_uselast
    assert_equal 'uselast', @editor.settings.get(:switchbuf)
  end

  def test_swb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set swb=useopen,split'))
    assert_equal 'useopen,split', @editor.settings.get(:switchbuf)
  end
end

class TestFileformat < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_detects_unix_format
    f = Tempfile.new(['ff_unix', '.txt'])
    f.binmode
    f.write("line1\nline2\nline3\n")
    f.close
    @editor.open(f.path)
    assert_equal 'unix', @editor.current_buffer.fileformat
    assert_equal %w[line1 line2 line3], @editor.buffer_of_lines
  ensure
    f&.unlink
  end

  def test_detects_dos_format
    f = Tempfile.new(['ff_dos', '.txt'])
    f.binmode
    f.write("line1\r\nline2\r\nline3\r\n")
    f.close
    @editor.open(f.path)
    assert_equal 'dos', @editor.current_buffer.fileformat
    assert_equal %w[line1 line2 line3], @editor.buffer_of_lines
  ensure
    f&.unlink
  end

  def test_detects_mac_format
    f = Tempfile.new(['ff_mac', '.txt'])
    f.binmode
    f.write("line1\rline2\rline3\r")
    f.close
    @editor.open(f.path)
    assert_equal 'mac', @editor.current_buffer.fileformat
    assert_equal %w[line1 line2 line3], @editor.buffer_of_lines
  ensure
    f&.unlink
  end

  def test_save_uses_buffer_fileformat_dos
    f = Tempfile.new(['ff_save', '.txt'])
    f.binmode
    f.write("a\nb\n")
    f.close
    @editor.open(f.path)
    @editor.current_buffer.fileformat = 'dos'
    @editor.save
    contents = File.binread(f.path)
    assert_equal "a\r\nb\r\n", contents
  ensure
    f&.unlink
  end

  def test_save_unix_format
    f = Tempfile.new(['ff_save', '.txt'])
    f.binmode
    f.write("a\nb\n")
    f.close
    @editor.open(f.path)
    @editor.current_buffer.fileformat = 'unix'
    @editor.save
    contents = File.binread(f.path)
    assert_equal "a\nb\n", contents
  ensure
    f&.unlink
  end
end

class TestSwapfileStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:swapfile)
  end

  def test_swf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set noswapfile'))
    assert_equal false, @editor.settings.get(:swapfile)
  end
end

class TestDirectoryStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_tmp
    assert_match(%r{/tmp}, @editor.settings.get(:directory))
  end

  def test_dir_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set dir=/var/tmp'))
    assert_equal '/var/tmp', @editor.settings.get(:directory)
  end
end

class TestUpdatecountStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_two_hundred
    assert_equal 200, @editor.settings.get(:updatecount)
  end

  def test_uc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set uc=0'))
    assert_equal 0, @editor.settings.get(:updatecount)
  end
end

class TestViewdirStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default
    assert_match(%r{view}, @editor.settings.get(:viewdir))
  end

  def test_vdir_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vdir=~/.cache/rvim/view'))
    assert_equal '~/.cache/rvim/view', @editor.settings.get(:viewdir)
  end
end

class TestViewoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_folds
    assert_match(/folds/, @editor.settings.get(:viewoptions))
  end

  def test_vop_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vop=folds,cursor'))
    assert_equal 'folds,cursor', @editor.settings.get(:viewoptions)
  end
end

class TestSessionoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_buffers
    assert_match(/buffers/, @editor.settings.get(:sessionoptions))
  end

  def test_ssop_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ssop=buffers,curdir'))
    assert_equal 'buffers,curdir', @editor.settings.get(:sessionoptions)
  end
end

class TestFileencoding < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_is_utf8
    assert_equal 'utf-8', @editor.settings.get(:fileencoding)
  end

  def test_fenc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fenc=latin1'))
    assert_equal 'latin1', @editor.settings.get(:fileencoding)
  end

  def test_save_writes_utf8_by_default
    f = Tempfile.new(['enc', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'café'
    @editor.save
    bytes = File.binread(f.path)
    # 'café' in UTF-8 is c-a-f-é (with é = 0xC3 0xA9)
    assert_equal "caf\xC3\xA9\n".b, bytes.b
  ensure
    f&.unlink
  end

  def test_save_writes_latin1_when_setting_changes
    f = Tempfile.new(['enc', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'café'
    @editor.settings.set(:fileencoding, 'iso-8859-1')
    @editor.save
    bytes = File.binread(f.path)
    # In Latin-1, é is single byte 0xE9
    assert_equal "caf\xE9\n".b, bytes.b
  ensure
    f&.unlink
  end

  def test_save_handles_undecodable_chars_gracefully
    f = Tempfile.new(['enc', '.txt'])
    f.binmode; f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'☃ snowman'
    @editor.settings.set(:fileencoding, 'iso-8859-1')
    @editor.save
    # Should not raise; should write replacement char(s) for ☃
    bytes = File.binread(f.path)
    assert bytes.bytesize > 0
  ensure
    f&.unlink
  end
end

class TestBufferFileencodingDetection < Test::Unit::TestCase
  def test_loads_utf8_file
    f = Tempfile.new(['enc', '.txt'])
    f.binmode; f.write("café\n".encode('utf-8')); f.close
    buf = Rvim::Buffer.new(1, f.path)
    assert_equal 'café', buf.lines[0]
  ensure
    f&.unlink
  end

  def test_falls_back_to_ascii_8bit_for_invalid_utf8
    f = Tempfile.new(['enc', '.txt'])
    f.binmode; f.write("\xFF\xFE\xFD\n".b); f.close
    buf = Rvim::Buffer.new(1, f.path)
    # Doesn't raise; line content is forced to ASCII-8BIT
    refute_nil buf.lines[0]
  ensure
    f&.unlink
  end
end

class TestViminfoStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_default_string
    assert_match(/100/, @editor.settings.get(:viminfo))
  end

  def test_vi_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(":set vi='200,h"))
    assert_equal "'200,h", @editor.settings.get(:viminfo)
  end
end

class TestFileformatsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_unix_dos
    assert_equal 'unix,dos', @editor.settings.get(:fileformats)
  end

  def test_ffs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ffs=unix,dos,mac'))
    assert_equal 'unix,dos,mac', @editor.settings.get(:fileformats)
  end
end

class TestFileignorecaseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:fileignorecase)
  end

  def test_fic_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fic'))
    assert_equal true, @editor.settings.get(:fileignorecase)
  end
end

class TestWriteStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:write)
  end

  def test_set_nowrite
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nowrite'))
    assert_equal false, @editor.settings.get(:write)
  end
end

class TestWriteanyStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:writeany)
  end

  def test_wa_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wa'))
    assert_equal true, @editor.settings.get(:writeany)
  end
end

class TestWritedelayStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:writedelay)
  end

  def test_wd_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wd=100'))
    assert_equal 100, @editor.settings.get(:writedelay)
  end
end

class TestAutowriteallStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:autowriteall)
  end

  def test_awa_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set awa'))
    assert_equal true, @editor.settings.get(:autowriteall)
  end
end

class TestFsyncStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:fsync)
  end

  def test_fs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fs'))
    assert_equal true, @editor.settings.get(:fsync)
  end
end

class TestAutowrite < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_off_by_default
    assert_equal false, @editor.settings.get(:autowrite)
  end

  def test_aw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set aw'))
    assert_equal true, @editor.settings.get(:autowrite)
  end

  def test_cycle_buffer_writes_when_aw_on
    Dir.mktmpdir do |dir|
      a = File.join(dir, 'a.txt')
      b = File.join(dir, 'b.txt')
      File.write(a, "first\n")
      File.write(b, "second\n")
      @editor.open(a)
      @editor.open(b)

      # Switch back to a, modify
      @editor.swap_to_buffer(@editor.buffers.values.find { |buf| buf.filepath == a })
      @editor.buffer_of_lines[0] = +'changed'
      @editor.modified = true

      @editor.settings.set(:autowrite, true)
      @editor.cycle_buffer(+1)

      contents = File.read(a)
      assert_match(/changed/, contents)
    end
  end

  def test_cycle_buffer_no_write_when_aw_off
    Dir.mktmpdir do |dir|
      a = File.join(dir, 'a.txt')
      b = File.join(dir, 'b.txt')
      File.write(a, "first\n")
      File.write(b, "second\n")
      @editor.open(a)
      @editor.open(b)
      @editor.swap_to_buffer(@editor.buffers.values.find { |buf| buf.filepath == a })
      @editor.buffer_of_lines[0] = +'changed'
      @editor.modified = true

      @editor.settings.set(:autowrite, false)
      @editor.cycle_buffer(+1)

      contents = File.read(a)
      refute_match(/changed/, contents)
    end
  end
end

class TestViminfofileStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:viminfofile)
  end

  def test_vif_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vif=~/.cache/rvim/info'))
    assert_equal '~/.cache/rvim/info', @editor.settings.get(:viminfofile)
  end
end

class TestBackupSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:backup)
  end

  def test_bk_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set bk'))
    assert_equal true, @editor.settings.get(:backup)
  end

  def test_save_writes_backup_when_on
    f = Tempfile.new(['bk', '.txt'])
    f.binmode; f.write("original\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'modified'
    @editor.settings.set(:backup, true)
    @editor.save
    backup = "#{f.path}~"
    assert File.exist?(backup), "expected backup at #{backup}"
    assert_equal "original\n", File.binread(backup)
    assert_match(/modified/, File.read(f.path))
  ensure
    f&.unlink
    File.delete("#{f.path}~") if f && File.exist?("#{f.path}~")
  end

  def test_save_no_backup_when_off
    f = Tempfile.new(['bk', '.txt'])
    f.binmode; f.write("original\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'modified'
    @editor.settings.set(:backup, false)
    @editor.save
    refute File.exist?("#{f.path}~")
  ensure
    f&.unlink
  end

  def test_save_skips_backup_when_no_existing_file
    Dir.mktmpdir do |dir|
      target = File.join(dir, 'new.txt')
      @editor.instance_variable_set(:@buffer_of_lines, ['hello'.dup])
      @editor.instance_variable_set(:@filepath, target)
      @editor.settings.set(:backup, true)
      @editor.save
      refute File.exist?("#{target}~")
    end
  end
end
