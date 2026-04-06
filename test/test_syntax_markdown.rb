# frozen_string_literal: true

require_relative 'test_helper'

class TestSyntaxMarkdown < Test::Unit::TestCase
  def test_heading
    segs = Rvim::Syntax.highlight('# Hello', :markdown)
    assert(segs.find { |_, _, c| c == :Title })
  end

  def test_heading_h6
    segs = Rvim::Syntax.highlight('###### deep', :markdown)
    assert(segs.find { |_, _, c| c == :Title })
  end

  def test_code_span
    segs = Rvim::Syntax.highlight('use `rake test` here', :markdown)
    assert(segs.find { |_, _, c| c == :String })
  end

  def test_bold
    segs = Rvim::Syntax.highlight('this is **bold** text', :markdown)
    assert(segs.find { |_, _, c| c == :Bold })
  end

  def test_italic
    segs = Rvim::Syntax.highlight('an *italic* word', :markdown)
    assert(segs.find { |_, _, c| c == :Italic })
  end

  def test_link
    segs = Rvim::Syntax.highlight('see [docs](https://x.com)', :markdown)
    assert(segs.find { |_, _, c| c == :Link })
  end

  def test_bullet
    segs = Rvim::Syntax.highlight('- item one', :markdown)
    assert(segs.find { |_, _, c| c == :Special })
  end

  def test_detect_language_md
    assert_equal :markdown, Rvim::Syntax.detect_language('foo.md')
    assert_equal :markdown, Rvim::Syntax.detect_language('README.markdown')
  end

  def test_code_span_dominates_emphasis
    segs = Rvim::Syntax.highlight('`*not italic*`', :markdown)
    code = segs.find { |_, _, c| c == :String }
    italic = segs.find { |_, _, c| c == :Italic }
    assert_not_nil code
    assert_nil italic
  end
end
