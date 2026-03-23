# frozen_string_literal: true

require_relative 'test_helper'

class TestListView < Test::Unit::TestCase
  def test_page_returns_first_n_minus_one
    v = Rvim::ListView.new(%w[a b c d e])
    assert_equal %w[a b c], v.page(4)
  end

  def test_more_true_when_remaining
    v = Rvim::ListView.new(%w[a b c d e])
    assert v.more?(4)
  end

  def test_more_false_on_last_page
    v = Rvim::ListView.new(%w[a b c])
    assert_equal false, v.more?(5)
  end

  def test_advance_moves_cursor
    v = Rvim::ListView.new(%w[a b c d e])
    v.advance!(4)
    assert_equal %w[d e], v.page(4)
  end

  def test_empty
    assert Rvim::ListView.new([]).empty?
  end
end
