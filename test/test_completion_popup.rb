# frozen_string_literal: true

require_relative 'test_helper'

class TestCompletionPopup < Test::Unit::TestCase
  def test_initial_state
    p = Rvim::CompletionPopup.new(contents: %w[alpha beta gamma])
    assert_equal 0, p.pointer
    assert_equal 0, p.scroll_top
    assert_equal 3, p.size
    assert_equal 5, p.width # longest is 5 ("alpha", "gamma")
    assert_equal false, p.empty?
  end

  def test_pointer_clamps
    p = Rvim::CompletionPopup.new(contents: %w[a b c])
    p.pointer = -5
    assert_equal 0, p.pointer
    p.pointer = 99
    assert_equal 2, p.pointer
  end

  def test_pointer_advances_scroll_top
    p = Rvim::CompletionPopup.new(contents: (1..20).map(&:to_s), max_height: 5)
    p.pointer = 4
    assert_equal 0, p.scroll_top # still in window
    p.pointer = 5
    assert_equal 1, p.scroll_top # advanced
    p.pointer = 19
    assert_equal 15, p.scroll_top # last entries visible
  end

  def test_pointer_back_pulls_scroll_top
    p = Rvim::CompletionPopup.new(contents: (1..20).map(&:to_s), max_height: 5)
    p.pointer = 19
    assert_equal 15, p.scroll_top
    p.pointer = 14
    assert_equal 14, p.scroll_top
  end

  def test_visible_range
    p = Rvim::CompletionPopup.new(contents: (1..20).map(&:to_s), max_height: 5)
    assert_equal (0...5), p.visible_range
    p.pointer = 10
    assert_equal (6...11), p.visible_range
  end

  def test_visible_height_clamps_to_size
    p = Rvim::CompletionPopup.new(contents: %w[a b c], max_height: 8)
    assert_equal 3, p.visible_height
  end

  def test_width_clamps_to_max
    p = Rvim::CompletionPopup.new(contents: ['a' * 100], max_width: 30)
    assert_equal 30, p.width
  end

  def test_needs_scrollbar
    short = Rvim::CompletionPopup.new(contents: %w[a b], max_height: 5)
    long = Rvim::CompletionPopup.new(contents: (1..10).map(&:to_s), max_height: 5)
    refute short.needs_scrollbar?
    assert long.needs_scrollbar?
  end

  def test_empty_contents
    p = Rvim::CompletionPopup.new(contents: [])
    assert p.empty?
    assert_equal 0, p.size
    assert_equal 0, p.width
    assert_equal (0...0), p.visible_range
  end
end
