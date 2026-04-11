# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'set'

class TestPumheight < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def test_default_is_zero_meaning_use_struct_default
    assert_equal 0, @editor.settings.get(:pumheight)
  end

  def test_ph_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ph=3'))
    assert_equal 3, @editor.settings.get(:pumheight)
  end

  def test_completion_popup_uses_pumheight_when_set
    @editor.settings.set(:pumheight, 3)
    @editor.instance_variable_set(:@buffer_of_lines, ['hello hero help happy hi'.dup, 'he'.dup])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.send(:start_completion, +1)
    assert_equal 3, @editor.completion_popup.max_height
  end

  def test_completion_popup_uses_struct_default_when_zero
    @editor.settings.set(:pumheight, 0)
    @editor.instance_variable_set(:@buffer_of_lines, ['hello hero help'.dup, 'he'.dup])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.send(:start_completion, +1)
    assert_equal Rvim::CompletionPopup::DEFAULT_MAX_HEIGHT, @editor.completion_popup.max_height
  end
end

class TestLinebreak < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_breaks_at_width
    @editor.settings.set(:linebreak, false)
    out = @screen.send(:split_line_segments, 'hello world how are you doing', 12)
    # First segment is exactly 12 chars; word may be split mid-way
    assert_equal 12, out[0][1].length
  end

  def test_linebreak_on_breaks_at_word
    @editor.settings.set(:linebreak, true)
    out = @screen.send(:split_line_segments, 'hello world how are you', 12)
    # 'hello world ' (12 chars with trailing space ends at word boundary)
    assert_equal 'hello world ', out[0][1]
    assert_equal 'how are you', out[1][1]
  end

  def test_linebreak_lbr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lbr'))
    assert_equal true, @editor.settings.get(:linebreak)
  end

  def test_linebreak_falls_through_for_unbreakable
    @editor.settings.set(:linebreak, true)
    # No spaces: falls through to default char-width split
    out = @screen.send(:split_line_segments, 'aaaaaaaaaaaaaaaaaaaa', 5)
    assert_equal 4, out.size # 20 chars / 5 = 4 segments
    out.each { |_, seg| assert_equal 5, seg.length }
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
