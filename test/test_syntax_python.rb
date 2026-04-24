# frozen_string_literal: true

require_relative 'test_helper'

class TestSyntaxPython < Test::Unit::TestCase
  def test_def_keyword
    segs = Rvim::Syntax.highlight('def foo():', :python)
    assert(segs.find { |_, _, c| c == :Keyword })
  end

  def test_string
    segs = Rvim::Syntax.highlight("x = 'hello'", :python)
    assert(segs.find { |_, _, c| c == :String })
  end

  def test_triple_quoted
    segs = Rvim::Syntax.highlight('"""docstring"""', :python)
    assert(segs.find { |_, _, c| c == :String })
  end

  def test_decorator
    segs = Rvim::Syntax.highlight('@property', :python)
    assert(segs.find { |_, _, c| c == :PreProc })
  end

  def test_comment
    segs = Rvim::Syntax.highlight('# noqa', :python)
    assert(segs.find { |_, _, c| c == :Comment })
  end

  def test_detect_language
    assert_equal :python, Rvim::Syntax.detect_language('foo.py')
    assert_equal :python, Rvim::Syntax.detect_language('main.pyw')
  end
end
