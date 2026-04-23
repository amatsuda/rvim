# frozen_string_literal: true

require_relative 'test_helper'

class TestSentenceTextObject < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'Hello there. World how are you?'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 6) # on 't' of 'there'
  end

  def find_sentence(inclusive)
    Rvim::TextObject.find('s', @editor, inclusive: inclusive)
  end

  def test_inner_sentence_excludes_trailing_space
    sel = find_sentence(false)
    refute_nil sel
    # 'Hello there.' — bytes 0..11 (the period at byte 11)
    assert_equal [0, 0], [sel.start_line, sel.start_col]
    assert_equal [0, 11], [sel.end_line, sel.end_col]
  end

  def test_around_sentence_includes_trailing_space
    sel = find_sentence(true)
    refute_nil sel
    # 'Hello there. ' — bytes 0..12 (period + one space)
    assert_equal [0, 0], [sel.start_line, sel.start_col]
    assert_equal [0, 12], [sel.end_line, sel.end_col]
  end

  def test_second_sentence_inner
    @editor.instance_variable_set(:@byte_pointer, 14) # on 'W' of 'World'
    sel = find_sentence(false)
    refute_nil sel
    # Sentence start is 'W' at byte 13 (one non-blank past the period at 11).
    assert_equal [0, 13], [sel.start_line, sel.start_col]
    # Sentence ends at the '?' at byte 30.
    assert_equal [0, 30], [sel.end_line, sel.end_col]
  end

  def test_no_punctuation_returns_full_buffer
    @editor.instance_variable_set(:@buffer_of_lines, [+'no punctuation here'])
    @editor.instance_variable_set(:@byte_pointer, 5)
    sel = find_sentence(false)
    refute_nil sel
    assert_equal [0, 0], [sel.start_line, sel.start_col]
    assert_equal [0, 18], [sel.end_line, sel.end_col]
  end

  def test_empty_buffer_returns_nil
    @editor.instance_variable_set(:@buffer_of_lines, [])
    sel = find_sentence(false)
    assert_nil sel
  end
end
