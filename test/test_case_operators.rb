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

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def fire_g_then(letter)
    # Step 1: g prefix sets a waiting_proc
    @editor.send(:rvim_g_prefix, nil, arg: nil)
    # Step 2: first letter ('u'/'U'/'~') goes through the waiting_proc
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
    # Step 3: caller dispatches the next key via update
  end

  def test_guu_lowercases_line
    fire_g_then('u')
    @editor.update(k('u'))
    assert_equal 'hello', @editor.buffer_of_lines[0]
    assert_equal 'World', @editor.buffer_of_lines[1]
  end

  def test_gUU_uppercases_line
    fire_g_then('U')
    @editor.update(k('U'))
    assert_equal 'HELLO', @editor.buffer_of_lines[0]
    assert_equal 'World', @editor.buffer_of_lines[1]
  end

  def test_g_tilde_tilde_toggles_line
    @editor.instance_variable_set(:@buffer_of_lines, [+'Hello'])
    fire_g_then('~')
    @editor.update(k('~'))
    assert_equal 'hELLO', @editor.buffer_of_lines[0]
  end

  def test_count_prefix_extends_to_multiple_lines
    @editor.send(:rvim_g_prefix, nil, arg: 2)
    @editor.instance_variable_get(:@waiting_proc).call('U', nil)
    @editor.update(k('U'))
    assert_equal 'HELLO', @editor.buffer_of_lines[0]
    assert_equal 'WORLD', @editor.buffer_of_lines[1]
  end

  def test_mismatched_second_key_motion_path
    # 'gu' then 'x' is treated as a motion. 'x' deletes a char in vi_command
    # which IS a destructive op, so to keep this test sane we instead use
    # a key that cleanly clears state without changing the buffer: use
    # backspace which Reline binds to ed_prev_char (no-op at start).
    fire_g_then('u')
    @editor.update(k("\b"))
    # Pending state cleared, no case op since pre==post
    assert_equal 'Hello', @editor.buffer_of_lines[0]
  end
end

class TestMotionCaseOperators < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def buf(*lines, line: 0, byte: 0)
    @editor.instance_variable_set(:@buffer_of_lines, lines.map { |l| +l })
    @editor.instance_variable_set(:@line_index, line)
    @editor.instance_variable_set(:@byte_pointer, byte)
  end

  def fire_g_then(letter)
    @editor.send(:rvim_g_prefix, nil, arg: nil)
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
  end

  def test_gu_dollar_lowercases_to_eol
    buf('Hello WORLD')
    fire_g_then('u')
    @editor.update(k('$'))
    assert_equal 'hello world', @editor.buffer_of_lines[0]
  end

  def test_gU_dollar_uppercases_to_eol
    buf('hello world')
    fire_g_then('U')
    @editor.update(k('$'))
    assert_equal 'HELLO WORLD', @editor.buffer_of_lines[0]
  end

  def test_gu_w_lowercases_word
    buf('HELLO world')
    fire_g_then('u')
    @editor.update(k('w'))
    # 'w' lands on 'w' of 'world' (byte 6); exclusive end → affects bytes 0..5
    # ("HELLO ") which uppercase chars become 'hello '
    assert_equal 'hello world', @editor.buffer_of_lines[0]
  end

  def test_g_tilde_dollar_toggles_to_eol
    buf('Hello World')
    fire_g_then('~')
    @editor.update(k('$'))
    assert_equal 'hELLO wORLD', @editor.buffer_of_lines[0]
  end

  def test_gu_iw_lowercases_inner_word
    buf('foo BAR baz', byte: 4) # cursor on 'B'
    fire_g_then('u')
    @editor.update(k('i'))
    @editor.update(k('w'))
    assert_equal 'foo bar baz', @editor.buffer_of_lines[0]
  end

  def test_gU_aw_uppercases_around_word
    buf('foo bar baz', byte: 4)
    fire_g_then('U')
    @editor.update(k('a'))
    @editor.update(k('w'))
    # 'aw' includes trailing whitespace, but case op only affects letters
    assert_equal 'foo BAR baz', @editor.buffer_of_lines[0]
  end

  def test_pending_state_cleared_after_motion
    buf('Hello')
    fire_g_then('u')
    assert_equal :lowercase, @editor.instance_variable_get(:@rvim_pending_case_op)
    @editor.update(k('$'))
    assert_nil @editor.instance_variable_get(:@rvim_pending_case_op)
  end
end
