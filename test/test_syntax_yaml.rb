# frozen_string_literal: true

require_relative 'test_helper'

class TestSyntaxYaml < Test::Unit::TestCase
  def test_key
    segs = Rvim::Syntax.highlight('name: rvim', :yaml)
    assert(segs.find { |_, _, c| c == :Identifier })
  end

  def test_string
    segs = Rvim::Syntax.highlight('name: "rvim"', :yaml)
    assert(segs.find { |_, _, c| c == :String })
  end

  def test_comment
    segs = Rvim::Syntax.highlight('# note', :yaml)
    assert(segs.find { |_, _, c| c == :Comment })
  end

  def test_boolean
    %w[true false null].each do |lit|
      segs = Rvim::Syntax.highlight(lit, :yaml)
      assert(segs.find { |_, _, c| c == :Keyword }, "#{lit} should be Keyword")
    end
  end

  def test_document_marker
    segs = Rvim::Syntax.highlight('---', :yaml)
    assert(segs.find { |_, _, c| c == :PreProc })
  end

  def test_detect_language
    assert_equal :yaml, Rvim::Syntax.detect_language('config.yml')
    assert_equal :yaml, Rvim::Syntax.detect_language('config.yaml')
  end
end
