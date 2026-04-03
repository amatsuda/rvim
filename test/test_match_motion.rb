# frozen_string_literal: true

require_relative 'test_helper'

class TestMatchMotionAlgo < Test::Unit::TestCase
  def m(buf, li, bp)
    Rvim::MatchMotion.match_at(buf, li, bp)
  end

  def test_open_paren_jumps_forward
    buf = ['(hello)']
    assert_equal [0, 6], m(buf, 0, 0)
  end

  def test_close_paren_jumps_back
    buf = ['(hello)']
    assert_equal [0, 0], m(buf, 0, 6)
  end

  def test_brackets
    buf = ['arr = [1, 2, 3]']
    assert_equal [0, 14], m(buf, 0, 6)
    assert_equal [0, 6], m(buf, 0, 14)
  end

  def test_braces
    buf = ['{ a: 1, b: 2 }']
    assert_equal [0, 13], m(buf, 0, 0)
    assert_equal [0, 0], m(buf, 0, 13)
  end

  def test_nested
    buf = ['((a)b)']
    # outer (
    assert_equal [0, 5], m(buf, 0, 0)
    # inner (
    assert_equal [0, 3], m(buf, 0, 1)
    # inner )
    assert_equal [0, 1], m(buf, 0, 3)
    # outer )
    assert_equal [0, 0], m(buf, 0, 5)
  end

  def test_multi_line_forward
    buf = ['def foo(', '  arg', ')']
    assert_equal [2, 0], m(buf, 0, 7)
  end

  def test_multi_line_backward
    buf = ['def foo(', '  arg', ')']
    assert_equal [0, 7], m(buf, 2, 0)
  end

  def test_off_bracket_scans_forward_on_line
    buf = ['x = (a + b)']
    assert_equal [0, 10], m(buf, 0, 0) # cursor on 'x', scan forward to '(' at 4, match at 10
  end

  def test_off_bracket_no_bracket_on_line
    buf = ['no brackets here']
    assert_nil m(buf, 0, 0)
  end

  def test_unbalanced
    buf = ['(unbalanced']
    assert_nil m(buf, 0, 0)
  end

  def test_unbalanced_close
    buf = ['unbalanced)']
    assert_nil m(buf, 0, 10)
  end

  def test_mixed_brackets_dont_cross_match
    buf = ['([)]']
    # ( at 0 should match ) at 2 (since we count balanced parens only,
    # ignoring [). The simple algo only counts the same family — so [
    # is ignored when scanning ()-pairs.
    assert_equal [0, 2], m(buf, 0, 0)
  end

  def test_empty_buffer
    assert_nil m([''], 0, 0)
  end
end

class TestMatchMotionDispatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def test_dispatch_moves_cursor
    @editor.instance_variable_set(:@buffer_of_lines, ['(hello)'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:rvim_match_motion, nil)
    assert_equal 0, @editor.line_index
    assert_equal 6, @editor.byte_pointer
  end

  def test_dispatch_pushes_jump
    @editor.instance_variable_set(:@buffer_of_lines, ['(hello)'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    initial_jump_size = @editor.jump_list.size
    @editor.send(:rvim_match_motion, nil)
    assert @editor.jump_list.size > initial_jump_size
  end

  def test_dispatch_no_op_when_no_bracket
    @editor.instance_variable_set(:@buffer_of_lines, ['no brackets'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 3)
    @editor.send(:rvim_match_motion, nil)
    assert_equal 3, @editor.byte_pointer
  end
end
