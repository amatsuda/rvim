# frozen_string_literal: true

require_relative 'test_helper'

# Regression: pasting clipboard content that arrives as ASCII-8BIT-tagged
# or with otherwise invalid encoding labels used to raise
# "invalid byte sequence in UTF-8" inside paste_char_after etc., because
# String#split couldn't operate on the mislabeled bytes.
class TestPasteMultibyte < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+''])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def make_clipboard_blob(text)
    # Simulate `pbpaste` returning bytes labeled as ASCII-8BIT.
    raw = text.dup.force_encoding(Encoding::ASCII_8BIT)
    raw
  end

  def test_paste_japanese_from_ascii_8bit_string
    blob = make_clipboard_blob('あいうえお')
    @editor.write_register(blob, :char, register: '"')
    @editor.send(:rvim_paste_after, nil)
    assert_equal 'あいうえお', @editor.buffer_of_lines[0]
  end

  def test_paste_with_invalid_bytes_scrubs_safely
    bad = String.new("good\xE3bad", encoding: Encoding::UTF_8)
    refute bad.valid_encoding?
    @editor.write_register(bad, :char, register: '"')
    assert_nothing_raised { @editor.send(:rvim_paste_after, nil) }
  end

  def test_system_clipboard_read_returns_valid_utf8
    # Stub the tool to return raw bytes labeled ASCII-8BIT.
    Rvim::SystemClipboard.singleton_class.alias_method(:_orig_read, :read)
    Rvim::SystemClipboard.define_singleton_method(:read) do
      'あいうえお'.dup.force_encoding(Encoding::ASCII_8BIT)
    end

    Rvim::SystemClipboard.singleton_class.remove_method(:read)
    Rvim::SystemClipboard.singleton_class.alias_method(:read, :_orig_read)
  ensure
    Rvim::SystemClipboard.singleton_class.alias_method(:read, :_orig_read) if Rvim::SystemClipboard.singleton_class.method_defined?(:_orig_read)
  end

  def test_paste_lines_after_with_japanese_blob
    blob = make_clipboard_blob("あ\nい\nう")
    @editor.write_register(blob, :line, register: '"')
    @editor.send(:rvim_paste_after, nil)
    assert_includes @editor.buffer_of_lines, 'あ'
    assert_includes @editor.buffer_of_lines, 'い'
    assert_includes @editor.buffer_of_lines, 'う'
  end

  def test_ensure_utf8_helper
    bad = String.new("good\xE3bad", encoding: Encoding::ASCII_8BIT)
    out = @editor.send(:ensure_utf8, bad)
    assert_equal Encoding::UTF_8, out.encoding
    assert out.valid_encoding?
  end
end
