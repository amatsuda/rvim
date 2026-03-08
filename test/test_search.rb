# frozen_string_literal: true

require_relative 'test_helper'

class TestSearch < Test::Unit::TestCase
  def test_scan_basic_matches
    buf = ['hello world', 'foo bar', 'hello again']
    matches = Rvim::Search.scan(buf, 'hello')
    assert_equal [[0, 0, 4], [2, 0, 4]], matches
  end

  def test_scan_multiple_per_line
    matches = Rvim::Search.scan(['ababab'], 'ab')
    assert_equal [[0, 0, 1], [0, 2, 3], [0, 4, 5]], matches
  end

  def test_scan_regex_anchors
    matches = Rvim::Search.scan(['foo bar', 'foobar'], '\bfoo\b')
    assert_equal [[0, 0, 2]], matches
  end

  def test_scan_invalid_regex_returns_empty
    assert_equal [], Rvim::Search.scan(['foo'], '(unbalanced')
  end

  def test_scan_empty_pattern_returns_empty
    assert_equal [], Rvim::Search.scan(['foo'], '')
  end

  def test_scan_zero_width_pattern_does_not_loop
    # Zero-width matches like ^ aren't useful for jump-to behavior; we don't
    # emit them. The important property is that scan terminates, not the count.
    assert_nothing_raised { Rvim::Search.scan(['hi'], '^') }
  end

  def test_next_match_forward_advances
    matches = [[0, 0, 4], [2, 0, 4]]
    nxt = Rvim::Search.next_match(matches, 0, 0, :forward)
    assert_equal [2, 0, 4], nxt
  end

  def test_next_match_forward_wraps
    matches = [[0, 0, 4], [2, 0, 4]]
    nxt = Rvim::Search.next_match(matches, 5, 0, :forward)
    assert_equal [0, 0, 4], nxt
  end

  def test_next_match_backward_wraps
    matches = [[0, 0, 4], [2, 0, 4]]
    prv = Rvim::Search.next_match(matches, 0, 0, :backward)
    assert_equal [2, 0, 4], prv
  end

  def test_next_match_empty_returns_nil
    assert_nil Rvim::Search.next_match([], 0, 0, :forward)
  end
end
