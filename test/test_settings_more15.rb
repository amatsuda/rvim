# frozen_string_literal: true

require_relative 'test_helper'

class TestEqualOperator < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def fire_equal
    @editor.send(:rvim_equal_operator, nil)
  end

  def test_default_equalprg_empty_no_op
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    fire_equal
    @editor.update(k('='))
    assert_equal 'hello', @editor.buffer_of_lines[0] # unchanged
  end

  def test_equal_equal_runs_equalprg_on_current_line
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:equalprg, 'tr a-z A-Z')
    fire_equal
    @editor.update(k('='))
    assert_equal 'HELLO', @editor.buffer_of_lines[0]
  end

  def test_equal_with_motion_runs_on_range
    @editor.instance_variable_set(:@buffer_of_lines, [+'one', +'two', +'three'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:equalprg, 'tr a-z A-Z')
    fire_equal
    @editor.update(k('j'))
    # Motion j → line range 0..1 piped through tr
    assert_equal 'ONE', @editor.buffer_of_lines[0]
    assert_equal 'TWO', @editor.buffer_of_lines[1]
    assert_equal 'three', @editor.buffer_of_lines[2]
  end

  def test_equalprg_failure_keeps_buffer
    @editor.instance_variable_set(:@buffer_of_lines, [+'a', +'b'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:equalprg, 'false')
    fire_equal
    @editor.update(k('='))
    assert_equal %w[a b], @editor.buffer_of_lines
    assert_match(/equalprg/, @editor.status_message.to_s)
  end

  def test_ep_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ep=indent'))
    assert_equal 'indent', @editor.settings.get(:equalprg)
  end
end

class TestBreakindent < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:breakindent)
  end

  def test_bri_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set bri'))
    assert_equal true, @editor.settings.get(:breakindent)
  end

  def test_renders_indent_on_continuation
    @editor.settings.set(:breakindent, true)
    @editor.settings.set(:wrap, true)
    indented = '    ' + ('A' * 30)
    @editor.instance_variable_set(:@buffer_of_lines, [indented])
    buf = Rvim::Buffer.new(1, nil); buf.lines = [indented]
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf); win.row = 0; win.col = 0; win.width = 12; win.height = 5
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)

    out = @screen.send(:render_window, win)
    # Continuation segment should include the leading 4-space indent
    assert_match(/    A/, out)
  end
end

class TestFixendofline < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:fixendofline)
  end

  def test_fixeol_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nofixeol'))
    assert_equal false, @editor.settings.get(:fixendofline)
  end
end
