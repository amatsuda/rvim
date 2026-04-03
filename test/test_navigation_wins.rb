# frozen_string_literal: true

require_relative 'test_helper'

class TestViewportScroll < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
    # Open a buffer so we get a window initialized.
    @editor.instance_variable_set(:@buffer_of_lines, (1..100).map { |i| +"line #{i}" })
    @editor.instance_variable_set(:@line_index, 50)
    @editor.instance_variable_set(:@byte_pointer, 0)

    buf = Rvim::Buffer.new(1, nil)
    buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf)
    win.height = 21 # 20 content rows + 1 status row
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)
  end

  def fire_z(letter)
    @editor.send(:rvim_fold_prefix, nil, arg: nil)
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
  end

  def test_zz_centers
    fire_z('z')
    # content_rows = win.height - 1 = 20; center → cl - 10 = 40
    assert_equal 40, @editor.current_window.scroll_top
  end

  def test_zt_top
    fire_z('t')
    assert_equal 50, @editor.current_window.scroll_top
  end

  def test_zb_bottom
    fire_z('b')
    # bottom: cl - content_rows + 1 = 50 - 20 + 1 = 31
    assert_equal 31, @editor.current_window.scroll_top
  end

  def test_zz_clamps_at_top
    @editor.instance_variable_set(:@line_index, 3)
    fire_z('z')
    # 3 - 10 = -7 → clamp to 0
    assert_equal 0, @editor.current_window.scroll_top
  end

  def test_cursor_does_not_move_for_viewport_scroll
    fire_z('z')
    assert_equal 50, @editor.line_index
  end
end

class TestSentenceParagraphDispatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def k(ch, sym)
    Reline::Key.new(ch, sym, false)
  end

  def test_paragraph_forward_jumps_to_blank
    @editor.instance_variable_set(:@buffer_of_lines, ['p1a', 'p1b', '', 'p2a', 'p2b'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.update(k('}', :rvim_paragraph_forward))
    assert_equal 2, @editor.line_index
  end

  def test_paragraph_backward_jumps_to_blank
    @editor.instance_variable_set(:@buffer_of_lines, ['p1a', 'p1b', '', 'p2a', 'p2b'])
    @editor.instance_variable_set(:@line_index, 4)
    @editor.update(k('{', :rvim_paragraph_backward))
    assert_equal 2, @editor.line_index
  end

  def test_sentence_forward
    @editor.instance_variable_set(:@buffer_of_lines, ['First. Second.'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.update(k(')', :rvim_sentence_forward))
    assert_equal 7, @editor.byte_pointer
  end

  def test_sentence_backward
    @editor.instance_variable_set(:@buffer_of_lines, ['First. Second.'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 8)
    @editor.update(k('(', :rvim_sentence_backward))
    assert_equal 7, @editor.byte_pointer
  end
end

class TestGotoDefinition < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def test_gd_jumps_to_first_occurrence
    @editor.instance_variable_set(:@buffer_of_lines, ['def foo', '  body', 'end', '', 'foo()'])
    @editor.instance_variable_set(:@line_index, 4)
    @editor.instance_variable_set(:@byte_pointer, 0) # cursor on 'f' of foo()
    @editor.send(:goto_definition)
    assert_equal 0, @editor.line_index
    assert_equal 4, @editor.byte_pointer # 'foo' starts at byte 4 of 'def foo'
  end

  def test_gd_no_match_no_op
    @editor.instance_variable_set(:@buffer_of_lines, ['unique only'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:goto_definition)
    assert_equal 0, @editor.line_index
    assert_equal 0, @editor.byte_pointer
  end

  def test_gd_pushes_jump
    @editor.instance_variable_set(:@buffer_of_lines, ['foo', 'foo'])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 0)
    pre = @editor.jump_list.size
    @editor.send(:goto_definition)
    assert @editor.jump_list.size > pre
  end
end
