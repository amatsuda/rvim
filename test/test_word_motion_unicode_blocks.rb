# frozen_string_literal: true

require_relative 'test_helper'

# Vim's word motion treats different Unicode blocks (Latin, Hiragana,
# Katakana, CJK ideograph, etc.) as separate word classes — `w` stops
# at a script change. Without this, `dw` on "abcあいう" deleted the
# whole line minus the last char instead of just "abc".
class TestWordMotionUnicodeBlocks < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def setup_buffer(text, byte_pointer: 0)
    @editor.instance_variable_set(:@buffer_of_lines, [+text])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, byte_pointer)
  end

  def test_dw_at_latin_to_hiragana_boundary
    setup_buffer('abcあいう')
    send_keys('d', 'w')
    assert_equal 'あいう', @editor.buffer_of_lines[0]
  end

  def test_dw_at_hiragana_to_latin_boundary
    setup_buffer('あいうabc')
    send_keys('d', 'w')
    assert_equal 'abc', @editor.buffer_of_lines[0]
  end

  def test_dw_at_hiragana_to_kanji_boundary
    setup_buffer('あい漢字')
    send_keys('d', 'w')
    assert_equal '漢字', @editor.buffer_of_lines[0]
  end

  def test_dw_at_kanji_to_hiragana_boundary
    setup_buffer('漢字あい')
    send_keys('d', 'w')
    assert_equal 'あい', @editor.buffer_of_lines[0]
  end

  def test_dw_within_same_script_runs_to_next_run
    setup_buffer('abc def')
    send_keys('d', 'w')
    assert_equal 'def', @editor.buffer_of_lines[0]
  end

  def test_dW_big_word_treats_japanese_and_latin_as_one
    setup_buffer('abcあいう def')
    send_keys('d', 'W')
    assert_equal 'def', @editor.buffer_of_lines[0]
  end

  def test_word_class_classifies_hiragana
    assert_equal :hiragana, @editor.send(:word_class, 'あ', false)
    assert_equal :hiragana, @editor.send(:word_class, 'い', false)
  end

  def test_word_class_classifies_katakana
    assert_equal :katakana, @editor.send(:word_class, 'ア', false)
  end

  def test_word_class_classifies_cjk
    assert_equal :cjk_ideograph, @editor.send(:word_class, '漢', false)
  end

  def test_word_class_distinguishes_latin_from_hiragana
    refute_equal @editor.send(:word_class, 'a', false), @editor.send(:word_class, 'あ', false)
  end

  def test_word_class_big_collapses_all
    # With big=true (W/B/E motions), only space is a boundary.
    assert_equal :word, @editor.send(:word_class, 'a', true)
    assert_equal :word, @editor.send(:word_class, 'あ', true)
    assert_equal :word, @editor.send(:word_class, '!', true)
  end
end
