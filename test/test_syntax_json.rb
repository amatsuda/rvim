# frozen_string_literal: true

require_relative 'test_helper'

class TestSyntaxJson < Test::Unit::TestCase
  def test_string
    segs = Rvim::Syntax.highlight('"hello"', :json)
    assert(segs.find { |_, _, c| c == :green })
  end

  def test_number_int
    segs = Rvim::Syntax.highlight('42', :json)
    assert(segs.find { |_, _, c| c == :red })
  end

  def test_number_negative_float
    segs = Rvim::Syntax.highlight('-3.14', :json)
    assert(segs.find { |_, _, c| c == :red })
  end

  def test_true_false_null
    %w[true false null].each do |lit|
      segs = Rvim::Syntax.highlight(lit, :json)
      assert(segs.find { |_, _, c| c == :magenta }, "#{lit} should be magenta")
    end
  end

  def test_object
    segs = Rvim::Syntax.highlight('{"key": "value"}', :json)
    greens = segs.count { |_, _, c| c == :green }
    assert_equal 2, greens
  end

  def test_detect_language
    assert_equal :json, Rvim::Syntax.detect_language('foo.json')
  end
end
