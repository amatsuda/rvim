# frozen_string_literal: true

require_relative 'test_helper'

class TestSyntaxJavascript < Test::Unit::TestCase
  def test_function_keyword
    segs = Rvim::Syntax.highlight('function foo() {}', :javascript)
    assert(segs.find { |_, _, c| c == :Keyword })
  end

  def test_const_let_var
    %w[const let var].each do |kw|
      segs = Rvim::Syntax.highlight("#{kw} x = 1", :javascript)
      assert(segs.find { |_, _, c| c == :Keyword }, "#{kw} should highlight as Keyword")
    end
  end

  def test_double_quoted_string
    segs = Rvim::Syntax.highlight('let x = "hi"', :javascript)
    assert(segs.find { |_, _, c| c == :String })
  end

  def test_line_comment
    segs = Rvim::Syntax.highlight('// note', :javascript)
    assert(segs.find { |_, _, c| c == :Comment })
  end

  def test_block_comment
    segs = Rvim::Syntax.highlight('/* note */', :javascript)
    assert(segs.find { |_, _, c| c == :Comment })
  end

  def test_detect_language
    assert_equal :javascript, Rvim::Syntax.detect_language('foo.js')
    assert_equal :javascript, Rvim::Syntax.detect_language('app.tsx')
    assert_equal :javascript, Rvim::Syntax.detect_language('mod.mjs')
  end
end
