# frozen_string_literal: true

require_relative 'test_helper'

class TestSyntax < Test::Unit::TestCase
  def test_comment
    segs = Rvim::Syntax.highlight('# this is a comment', :ruby)
    assert_equal 1, segs.size
    assert_equal :Comment, segs[0][2]
  end

  def test_keyword
    segs = Rvim::Syntax.highlight('def foo', :ruby)
    keyword = segs.find { |_, _, c| c == :Keyword }
    assert_not_nil keyword
    assert_equal 0, keyword[0]
    assert_equal 2, keyword[1]
  end

  def test_string
    segs = Rvim::Syntax.highlight('puts "hello"', :ruby)
    str = segs.find { |_, _, c| c == :String }
    assert_not_nil str
    assert_equal 5, str[0]
  end

  def test_string_dominates_keyword
    segs = Rvim::Syntax.highlight('"def foo"', :ruby)
    string = segs.find { |_, _, c| c == :String }
    assert_not_nil string
    keyword = segs.find { |_, _, c| c == :Keyword }
    if keyword
      assert keyword[0] > string[1], 'keyword should be after the string'
    end
  end

  def test_number
    segs = Rvim::Syntax.highlight('x = 42', :ruby)
    num = segs.find { |_, _, c| c == :Number }
    assert_not_nil num
    assert_equal 4, num[0]
  end

  def test_symbol
    segs = Rvim::Syntax.highlight('h = { a: :foo }', :ruby)
    sym = segs.find { |_, _, c| c == :Symbol }
    assert_not_nil sym
  end

  def test_constant
    segs = Rvim::Syntax.highlight('class Foo', :ruby)
    const = segs.find { |_, _, c| c == :Constant }
    assert_not_nil const
  end

  def test_no_tokens_for_unknown_lang
    assert_equal [], Rvim::Syntax.highlight('def foo', :unknown)
  end

  def test_detect_language
    assert_equal :ruby, Rvim::Syntax.detect_language('foo.rb')
    assert_equal :ruby, Rvim::Syntax.detect_language('lib/foo.gemspec')
    assert_nil Rvim::Syntax.detect_language('foo.txt')
    assert_nil Rvim::Syntax.detect_language(nil)
  end
end
