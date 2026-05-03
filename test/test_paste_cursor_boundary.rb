# frozen_string_literal: true

require_relative 'test_helper'

# Regression: yl on a multibyte char then p on a new line crashed in
# Reline::Unicode.escape_for_print. Cause: paste_char_after set
# byte_pointer = insert_at + bytesize - 1, which for "あ" (3 bytes) lands
# at byte 2 — mid-codepoint. Reline's wrapped_cursor_position then
# byteslice(0, 2)'d the line, got "\xE3\x81" alone, and crashed.
class TestPasteCursorBoundary < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+''])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_paste_japanese_char_lands_on_char_boundary
    @editor.write_register('あ', :char, register: '"')
    @editor.send(:rvim_paste_after, nil)
    assert_equal 0, @editor.byte_pointer
    assert @editor.buffer_of_lines[0].valid_encoding?
  end

  def test_paste_ascii_char_still_lands_on_pasted_char
    @editor.instance_variable_set(:@buffer_of_lines, [+'X'])
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.write_register('a', :char, register: '"')
    @editor.send(:rvim_paste_after, nil)
    # 'X' + 'a' = 'Xa', cursor lands on 'a' at byte 1.
    assert_equal 1, @editor.byte_pointer
  end

  def test_paste_multichar_japanese_lands_on_last_char_start
    @editor.write_register('あい', :char, register: '"')
    @editor.send(:rvim_paste_after, nil)
    # buffer = "あい" (6 bytes), cursor on start of 'い' at byte 3.
    assert_equal 3, @editor.byte_pointer
    assert @editor.buffer_of_lines[0].valid_encoding?
  end

  def test_paste_then_render_does_not_raise
    @editor.write_register('あ', :char, register: '"')
    assert_nothing_raised do
      sym = @editor.send(:synthesize_key, 'p').method_symbol
      @editor.update(Reline::Key.new('p', sym, false))
    end
  end

  def test_yl_on_japanese_then_paste_round_trip
    @editor.instance_variable_set(:@buffer_of_lines, [+'あ', +''])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)

    send_keys('y', 'l')
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 0)
    send_keys('p')

    assert_equal 'あ', @editor.buffer_of_lines[1]
    assert_equal 0, @editor.byte_pointer
  end
end
