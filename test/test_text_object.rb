# frozen_string_literal: true

require_relative 'test_helper'

class TestTextObjectWord < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def place(line, byte)
    @editor.instance_variable_set(:@line_index, line)
    @editor.instance_variable_set(:@byte_pointer, byte)
  end

  def buffer(*lines)
    @editor.instance_variable_set(:@buffer_of_lines, lines)
  end

  def test_iw_on_word_middle
    buffer('hello world')
    place(0, 2) # cursor on 'l' of 'hello'
    sel = Rvim::TextObject.find('w', @editor, inclusive: false)
    assert_equal 0, sel.start_col
    assert_equal 4, sel.end_col # 'hello' bytes 0..4
  end

  def test_iw_on_whitespace_selects_run
    buffer('hello   world')
    place(0, 6) # in the spaces
    sel = Rvim::TextObject.find('w', @editor, inclusive: false)
    assert_equal 5, sel.start_col
    assert_equal 7, sel.end_col # three spaces 5..7
  end

  def test_aw_includes_trailing_space
    buffer('hello world')
    place(0, 2)
    sel = Rvim::TextObject.find('w', @editor, inclusive: true)
    assert_equal 0, sel.start_col
    assert_equal 5, sel.end_col # hello + space
  end

  def test_aw_at_eol_includes_leading_space
    buffer('hello world')
    place(0, 8) # in 'world'
    sel = Rvim::TextObject.find('w', @editor, inclusive: true)
    assert_equal 5, sel.start_col # leading space
    assert_equal 10, sel.end_col # end of line
  end

  def test_iW_treats_punct_as_part_of_word
    buffer('a-b c')
    place(0, 0)
    sel = Rvim::TextObject.find('W', @editor, inclusive: false)
    assert_equal 0, sel.start_col
    assert_equal 2, sel.end_col # 'a-b' as one WORD
  end

  def test_iw_separates_at_punct
    buffer('a-b')
    place(0, 0)
    sel = Rvim::TextObject.find('w', @editor, inclusive: false)
    assert_equal 0, sel.start_col
    assert_equal 0, sel.end_col # just 'a'
  end
end
