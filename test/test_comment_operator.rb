# frozen_string_literal: true

require_relative 'test_helper'

# Built-in gc operator + gcc line toggle (NeoVim 0.10 parity).

class TestCommentOperator < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def fire_g_then(letter)
    # Mirror what update would do: g triggers the prefix waiting_proc,
    # then the next character feeds into it.
    @editor.send(:rvim_g_prefix, nil, arg: nil)
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
  end

  def test_gcc_comments_current_line
    @editor.instance_variable_set(:@buffer_of_lines, [+'puts "hello"', +'puts "world"'])
    fire_g_then('c')
    @editor.update(k('c'))
    assert_equal '# puts "hello"', @editor.buffer_of_lines[0]
    assert_equal 'puts "world"',   @editor.buffer_of_lines[1]
  end

  def test_gcc_toggles_off_when_already_commented
    @editor.instance_variable_set(:@buffer_of_lines, [+'# already', +'plain'])
    fire_g_then('c')
    @editor.update(k('c'))
    assert_equal 'already', @editor.buffer_of_lines[0]
  end

  def test_gcc_preserves_indent
    @editor.instance_variable_set(:@buffer_of_lines, [+'  puts "hi"'])
    fire_g_then('c')
    @editor.update(k('c'))
    assert_equal '  # puts "hi"', @editor.buffer_of_lines[0]
  end

  def test_count_prefix_extends_to_multiple_lines
    @editor.instance_variable_set(:@buffer_of_lines, [+'a', +'b', +'c'])
    @editor.send(:rvim_g_prefix, nil, arg: 3)
    @editor.instance_variable_get(:@waiting_proc).call('c', nil)
    @editor.update(k('c'))
    assert_equal '# a', @editor.buffer_of_lines[0]
    assert_equal '# b', @editor.buffer_of_lines[1]
    assert_equal '# c', @editor.buffer_of_lines[2]
  end

  def test_block_comment_style
    @editor.settings.set(:commentstring, '/* %s */')
    @editor.instance_variable_set(:@buffer_of_lines, [+'foo()'])
    fire_g_then('c')
    @editor.update(k('c'))
    assert_equal '/* foo() */', @editor.buffer_of_lines[0]

    fire_g_then('c')
    @editor.update(k('c'))
    assert_equal 'foo()', @editor.buffer_of_lines[0]
  end

  def test_mixed_block_comments_when_any_uncommented
    # If any non-blank line in the range is uncommented, the toggle
    # direction is "comment all" — matching NeoVim's behavior.
    @editor.instance_variable_set(:@buffer_of_lines, [+'# already', +'plain', +'# also'])
    @editor.send(:rvim_g_prefix, nil, arg: 3)
    @editor.instance_variable_get(:@waiting_proc).call('c', nil)
    @editor.update(k('c'))
    assert_equal '# # already', @editor.buffer_of_lines[0]
    assert_equal '# plain',     @editor.buffer_of_lines[1]
    assert_equal '# # also',    @editor.buffer_of_lines[2]
  end

  def test_blank_lines_skipped_when_commenting
    @editor.instance_variable_set(:@buffer_of_lines, [+'a', +'', +'b'])
    @editor.send(:rvim_g_prefix, nil, arg: 3)
    @editor.instance_variable_get(:@waiting_proc).call('c', nil)
    @editor.update(k('c'))
    assert_equal '# a', @editor.buffer_of_lines[0]
    assert_equal '',    @editor.buffer_of_lines[1]
    assert_equal '# b', @editor.buffer_of_lines[2]
  end

  def test_gc_with_j_motion_comments_two_lines
    # gcj should comment current + next line (linewise motion).
    @editor.instance_variable_set(:@buffer_of_lines, [+'one', +'two', +'three'])
    fire_g_then('c')
    @editor.update(k('j'))
    assert_equal '# one', @editor.buffer_of_lines[0]
    assert_equal '# two', @editor.buffer_of_lines[1]
    assert_equal 'three', @editor.buffer_of_lines[2]
  end
end

class TestCommentOperatorVisual < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
    @editor.instance_variable_set(:@buffer_of_lines, [+'foo', +'bar', +'baz'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def k(ch)
    Reline::Key.new(ch, nil, false)
  end

  def enter_visual_line(start_line, end_line)
    @editor.instance_variable_set(:@visual_mode, :line)
    @editor.instance_variable_set(:@visual_anchor, [start_line, 0])
    @editor.instance_variable_set(:@line_index, end_line)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_visual_gc_comments_selection
    enter_visual_line(0, 1)
    assert @editor.send(:intercept_visual_key, k('g'))
    assert @editor.send(:intercept_visual_key, k('c'))
    assert_equal '# foo', @editor.buffer_of_lines[0]
    assert_equal '# bar', @editor.buffer_of_lines[1]
    assert_equal 'baz',   @editor.buffer_of_lines[2]
  end

  def test_visual_gc_uncomments_selection
    @editor.instance_variable_set(:@buffer_of_lines, [+'# a', +'# b', +'plain'])
    enter_visual_line(0, 1)
    @editor.send(:intercept_visual_key, k('g'))
    @editor.send(:intercept_visual_key, k('c'))
    assert_equal 'a',     @editor.buffer_of_lines[0]
    assert_equal 'b',     @editor.buffer_of_lines[1]
    assert_equal 'plain', @editor.buffer_of_lines[2]
  end
end
