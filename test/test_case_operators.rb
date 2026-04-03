# frozen_string_literal: true

require_relative 'test_helper'

class TestVisualCaseOperators < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
    @editor.instance_variable_set(:@buffer_of_lines, [+'Hello World'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def k(ch, sym = nil)
    Reline::Key.new(ch, sym, false)
  end

  def enter_visual(start_byte, end_byte)
    @editor.instance_variable_set(:@visual_mode, :char)
    @editor.instance_variable_set(:@visual_anchor, [0, start_byte])
    @editor.instance_variable_set(:@byte_pointer, end_byte)
  end

  def test_visual_u_lowercases
    enter_visual(0, 4)
    @editor.update(k('u'))
    assert_equal 'hello World', @editor.buffer_of_lines[0]
  end

  def test_visual_U_uppercases
    enter_visual(6, 10)
    @editor.update(k('U'))
    assert_equal 'Hello WORLD', @editor.buffer_of_lines[0]
  end

  def test_visual_tilde_toggles
    enter_visual(0, 4)
    @editor.update(k('~'))
    assert_equal 'hELLO World', @editor.buffer_of_lines[0]
  end
end

class TestLinewiseCaseOperators < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
    @editor.instance_variable_set(:@buffer_of_lines, [+'Hello', +'World'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def fire_g_pair(letter)
    @editor.send(:rvim_g_prefix, nil, arg: nil)
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
  end

  def test_guu_lowercases_line
    fire_g_pair('u')
    assert_equal 'hello', @editor.buffer_of_lines[0]
    assert_equal 'World', @editor.buffer_of_lines[1]
  end

  def test_gUU_uppercases_line
    fire_g_pair('U')
    assert_equal 'HELLO', @editor.buffer_of_lines[0]
    assert_equal 'World', @editor.buffer_of_lines[1]
  end

  def test_g_tilde_tilde_toggles_line
    @editor.instance_variable_set(:@buffer_of_lines, [+'Hello'])
    fire_g_pair('~')
    assert_equal 'hELLO', @editor.buffer_of_lines[0]
  end

  def test_count_prefix_extends_to_multiple_lines
    @editor.send(:rvim_g_prefix, nil, arg: 2)
    @editor.instance_variable_get(:@waiting_proc).call('U', nil)
    @editor.instance_variable_get(:@waiting_proc).call('U', nil)
    assert_equal 'HELLO', @editor.buffer_of_lines[0]
    assert_equal 'WORLD', @editor.buffer_of_lines[1]
  end

  def test_mismatched_second_key_no_op
    fire_g_pair_mixed = lambda do
      @editor.send(:rvim_g_prefix, nil, arg: nil)
      @editor.instance_variable_get(:@waiting_proc).call('u', nil)
      @editor.instance_variable_get(:@waiting_proc).call('x', nil)
    end
    fire_g_pair_mixed.call
    assert_equal 'Hello', @editor.buffer_of_lines[0]
  end
end
