# frozen_string_literal: true

require_relative 'test_helper'

class TestSyntaxShell < Test::Unit::TestCase
  def test_comment
    segs = Rvim::Syntax.highlight('# a comment', :shell)
    assert(segs.find { |_, _, c| c == :cyan })
  end

  def test_string_double
    segs = Rvim::Syntax.highlight('echo "hi"', :shell)
    assert(segs.find { |_, _, c| c == :green })
  end

  def test_string_single
    segs = Rvim::Syntax.highlight("echo 'hi'", :shell)
    assert(segs.find { |_, _, c| c == :green })
  end

  def test_variable_simple
    segs = Rvim::Syntax.highlight('echo $foo', :shell)
    assert(segs.find { |_, _, c| c == :yellow })
  end

  def test_variable_braces
    segs = Rvim::Syntax.highlight('echo ${foo}', :shell)
    assert(segs.find { |_, _, c| c == :yellow })
  end

  def test_keywords
    segs = Rvim::Syntax.highlight('if [ x ]; then echo a; fi', :shell)
    keywords = segs.count { |_, _, c| c == :magenta }
    assert keywords >= 3, "expected at least 3 keywords, got #{keywords}"
  end

  def test_for_loop
    segs = Rvim::Syntax.highlight('for x in 1 2 3; do echo $x; done', :shell)
    assert(segs.find { |_, _, c| c == :magenta })
    assert(segs.find { |_, _, c| c == :yellow })
  end

  def test_comment_dominates_other
    segs = Rvim::Syntax.highlight('# echo "hi" $foo', :shell)
    assert(segs.find { |_, _, c| c == :cyan })
    assert_nil segs.find { |_, _, c| c == :green }
    assert_nil segs.find { |_, _, c| c == :yellow }
  end

  def test_detect_language
    assert_equal :shell, Rvim::Syntax.detect_language('foo.sh')
    assert_equal :shell, Rvim::Syntax.detect_language('foo.bash')
    assert_equal :shell, Rvim::Syntax.detect_language('foo.zsh')
  end
end
