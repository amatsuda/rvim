# frozen_string_literal: true

require_relative 'test_helper'

# Regression: pressing `p` while the cursor was on a multibyte char
# inserted the pasted content one BYTE past the cursor — landing
# mid-codepoint. The buffer ended up with orphan continuation bytes
# and the next render crashed in escape_for_print.
class TestPasteAtMultibyteCursor < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def setup_buffer(text, byte_pointer: 0)
    @editor.instance_variable_set(:@buffer_of_lines, [+text])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, byte_pointer)
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_paste_ascii_after_japanese_cursor
    setup_buffer('あい', byte_pointer: 0) # on 'あ'
    @editor.write_register('X', :char, register: '"')
    send_keys('p')
    assert_equal 'あXい', @editor.buffer_of_lines[0]
    assert @editor.buffer_of_lines[0].valid_encoding?
  end

  def test_paste_japanese_after_japanese_cursor
    setup_buffer('あい', byte_pointer: 0)
    @editor.write_register('Z', :char, register: '"')
    @editor.write_register('う', :char, register: '"')
    send_keys('p')
    assert_equal 'あうい', @editor.buffer_of_lines[0]
    assert @editor.buffer_of_lines[0].valid_encoding?
  end

  def test_paste_after_second_japanese_char
    setup_buffer('あい', byte_pointer: 3) # on 'い'
    @editor.write_register('!', :char, register: '"')
    send_keys('p')
    assert_equal 'あい!', @editor.buffer_of_lines[0]
    assert @editor.buffer_of_lines[0].valid_encoding?
  end

  def test_paste_into_empty_line_unchanged
    setup_buffer('', byte_pointer: 0)
    @editor.write_register('hi', :char, register: '"')
    send_keys('p')
    assert_equal 'hi', @editor.buffer_of_lines[0]
  end

  def test_paste_after_ascii_cursor_still_advances_one_byte
    setup_buffer('abc', byte_pointer: 1) # on 'b'
    @editor.write_register('X', :char, register: '"')
    send_keys('p')
    assert_equal 'abXc', @editor.buffer_of_lines[0]
  end
end
