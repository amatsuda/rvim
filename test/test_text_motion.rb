# frozen_string_literal: true

require_relative 'test_helper'

class TestSentenceMotion < Test::Unit::TestCase
  def next_(buf, li, bp)
    Rvim::TextMotion.next_sentence(buf, li, bp)
  end

  def prev_(buf, li, bp)
    Rvim::TextMotion.prev_sentence(buf, li, bp)
  end

  def test_next_sentence_same_line
    buf = ['First. Second sentence.']
    # cursor at byte 0 (on 'F')
    li, bp = next_(buf, 0, 0)
    assert_equal 0, li
    assert_equal 7, bp # start of 'Second'
  end

  def test_next_sentence_crosses_line
    buf = ['Para one.', '', 'Para two.']
    li, bp = next_(buf, 0, 0)
    # Period at end of line 0, no following content on line 0 → next non-blank at line 2
    assert_equal 2, li
    assert_equal 0, bp
  end

  def test_next_sentence_at_eof_clamps
    buf = ['Final sentence.']
    li, bp = next_(buf, 0, 0)
    assert_equal 0, li
    assert_equal 14, bp
  end

  def test_prev_sentence_same_line
    buf = ['First. Second.']
    # cursor at byte 8 (on 'e' of Second)
    li, bp = prev_(buf, 0, 8)
    assert_equal 0, li
    assert_equal 7, bp # start of "Second" (after the '. ')
  end

  def test_prev_sentence_to_buffer_start
    buf = ['Hello world without punctuation']
    li, bp = prev_(buf, 0, 10)
    assert_equal 0, li
    assert_equal 0, bp
  end
end

class TestParagraphMotion < Test::Unit::TestCase
  def test_next_paragraph_finds_blank
    buf = ['line one', 'line two', '', 'line four']
    assert_equal 2, Rvim::TextMotion.next_paragraph(buf, 0)
  end

  def test_next_paragraph_no_blank_returns_last
    buf = ['line one', 'line two']
    assert_equal 1, Rvim::TextMotion.next_paragraph(buf, 0)
  end

  def test_prev_paragraph_finds_blank
    buf = ['p1a', 'p1b', '', 'p2a', 'p2b']
    assert_equal 2, Rvim::TextMotion.prev_paragraph(buf, 4)
  end

  def test_prev_paragraph_no_blank_returns_zero
    buf = ['p1a', 'p1b', 'p1c']
    assert_equal 0, Rvim::TextMotion.prev_paragraph(buf, 2)
  end
end
