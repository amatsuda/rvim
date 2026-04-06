# frozen_string_literal: true

require_relative 'test_helper'

class TestSyntaxShell < Test::Unit::TestCase
  def test_comment
    segs = Rvim::Syntax.highlight('# a comment', :shell)
    assert(segs.find { |_, _, c| c == :Comment })
  end

  def test_string_double
    segs = Rvim::Syntax.highlight('echo "hi"', :shell)
    assert(segs.find { |_, _, c| c == :String })
  end

  def test_string_single
    segs = Rvim::Syntax.highlight("echo 'hi'", :shell)
    assert(segs.find { |_, _, c| c == :String })
  end

  def test_variable_simple
    segs = Rvim::Syntax.highlight('echo $foo', :shell)
    assert(segs.find { |_, _, c| c == :Identifier })
  end

  def test_variable_braces
    segs = Rvim::Syntax.highlight('echo ${foo}', :shell)
    assert(segs.find { |_, _, c| c == :Identifier })
  end

  def test_keywords
    segs = Rvim::Syntax.highlight('if [ x ]; then echo a; fi', :shell)
    keywords = segs.count { |_, _, c| c == :Keyword }
    assert keywords >= 3, "expected at least 3 keywords, got #{keywords}"
  end

  def test_for_loop
    segs = Rvim::Syntax.highlight('for x in 1 2 3; do echo $x; done', :shell)
    assert(segs.find { |_, _, c| c == :Keyword })
    assert(segs.find { |_, _, c| c == :Identifier })
  end

  def test_comment_dominates_other
    segs = Rvim::Syntax.highlight('# echo "hi" $foo', :shell)
    assert(segs.find { |_, _, c| c == :Comment })
    assert_nil segs.find { |_, _, c| c == :String }
    assert_nil segs.find { |_, _, c| c == :Identifier }
  end

  def test_detect_language
    assert_equal :shell, Rvim::Syntax.detect_language('foo.sh')
    assert_equal :shell, Rvim::Syntax.detect_language('foo.bash')
    assert_equal :shell, Rvim::Syntax.detect_language('foo.zsh')
  end
end
