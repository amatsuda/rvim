# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

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
