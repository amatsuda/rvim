# frozen_string_literal: true

require_relative 'test_helper'

# Regression: word_class used to do `byte =~ /\w/` on a single-byte
# byteslice. On multibyte characters that byte was a UTF-8 leading or
# continuation byte (e.g. 0xE3 from 'あ'), and the match raised
# "invalid byte sequence in UTF-8". Word motions on Japanese / Cyrillic
# / emoji-bearing lines therefore crashed the editor.
class TestWordMotionMultibyte < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'あいうえお'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.config.editing_mode = :vi_command
  end

  def test_word_class_on_multibyte_does_not_raise
    line = +'あいうえお'
    assert_nothing_raised { @editor.send(:word_class, line.byteslice(0, 1), false) }
  end

  def test_word_class_classifies_hiragana_codepoint
    # Pass the full mbchar (the way word-motion callers do); expect the
    # specific Unicode-block class so 'abc' and 'あいう' are distinct
    # word groups for `w`/`b`/`e` motions.
    line = +'あいうえお'
    assert_equal :hiragana, @editor.send(:word_class, line.byteslice(0, 3), false)
  end

  def test_advance_word_start_on_japanese_does_not_raise
    assert_nothing_raised { @editor.send(:advance_word_start, big: false) }
  end

  def test_advance_word_end_on_japanese_does_not_raise
    assert_nothing_raised { @editor.send(:advance_word_end, big: false) }
  end

  def test_word_class_punctuation_still_classified
    assert_equal :punct, @editor.send(:word_class, '!', false)
  end

  def test_word_class_space_still_space
    assert_equal :space, @editor.send(:word_class, ' ', false)
  end

  def test_word_class_word_char
    assert_equal :word, @editor.send(:word_class, 'a', false)
  end
end
