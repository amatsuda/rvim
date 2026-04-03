# frozen_string_literal: true

require_relative 'test_helper'

class TestSortParse < Test::Unit::TestCase
  def test_parse_sort_no_args
    parsed = Rvim::Command.parse(':sort')
    assert_equal :sort, parsed.verb
    assert_equal '', parsed.arg
    assert_equal false, parsed.bang
    assert_nil parsed.range
  end

  def test_parse_sort_bang
    parsed = Rvim::Command.parse(':sort!')
    assert_equal true, parsed.bang
  end

  def test_parse_sort_flags
    parsed = Rvim::Command.parse(':sort un')
    assert_equal 'un', parsed.arg
  end

  def test_parse_sort_with_range
    parsed = Rvim::Command.parse(':3,7sort')
    assert_equal :sort, parsed.verb
    assert_equal [3, 7], parsed.range
  end

  def test_parse_sort_visual
    parsed = Rvim::Command.parse(":'<,'>sort")
    assert_equal :visual, parsed.range
  end

  def test_parse_sort_whole
    parsed = Rvim::Command.parse(':%sort!')
    assert_equal :whole, parsed.range
    assert_equal true, parsed.bang
  end
end

class TestSortExecute < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def buf(*lines)
    @editor.instance_variable_set(:@buffer_of_lines, lines.map { |l| +l })
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_sort_alphabetical
    buf('charlie', 'alpha', 'bravo')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':sort'))
    assert_equal %w[alpha bravo charlie], @editor.buffer_of_lines
  end

  def test_sort_reverse
    buf('a', 'c', 'b')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':sort!'))
    assert_equal %w[c b a], @editor.buffer_of_lines
  end

  def test_sort_unique
    buf('b', 'a', 'a', 'b', 'c')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':sort u'))
    assert_equal %w[a b c], @editor.buffer_of_lines
  end

  def test_sort_numeric
    buf('item 10', 'item 2', 'item 1')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':sort n'))
    assert_equal ['item 1', 'item 2', 'item 10'], @editor.buffer_of_lines
  end

  def test_sort_case_insensitive
    buf('Banana', 'apple', 'CHERRY')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':sort i'))
    assert_equal %w[apple Banana CHERRY], @editor.buffer_of_lines
  end

  def test_sort_range
    buf('keep1', 'c', 'a', 'b', 'keep2')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':2,4sort'))
    assert_equal %w[keep1 a b c keep2], @editor.buffer_of_lines
  end
end
