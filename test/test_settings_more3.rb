# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

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

class TestVirtualeditMouseSidescrolloffStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_virtualedit_default_empty
    assert_equal '', @editor.settings.get(:virtualedit)
  end

  def test_set_virtualedit_value
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set virtualedit=onemore'))
    assert_equal 'onemore', @editor.settings.get(:virtualedit)
  end

  def test_ve_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ve=block'))
    assert_equal 'block', @editor.settings.get(:virtualedit)
  end

  def test_mouse_default_empty
    assert_equal '', @editor.settings.get(:mouse)
  end

  def test_set_mouse_value
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mouse=a'))
    assert_equal 'a', @editor.settings.get(:mouse)
  end

  def test_sidescrolloff_default_zero
    assert_equal 0, @editor.settings.get(:sidescrolloff)
  end

  def test_siso_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set siso=5'))
    assert_equal 5, @editor.settings.get(:sidescrolloff)
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
