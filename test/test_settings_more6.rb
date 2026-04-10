# frozen_string_literal: true

require_relative 'test_helper'

class TestAutoindent < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def test_default_no_indent_carry
    @editor.instance_variable_set(:@buffer_of_lines, [+'    hello world'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 9) # after 'hello'
    @editor.send(:rvim_insert_newline, nil)
    assert_equal ['    hello', ' world'], @editor.buffer_of_lines
  end

  def test_autoindent_carries_leading_whitespace
    @editor.settings.set(:autoindent, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+'    hello world'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 9) # after 'hello'
    @editor.send(:rvim_insert_newline, nil)
    assert_equal ['    hello', '     world'], @editor.buffer_of_lines
    # Cursor lands at end of indent on new line
    assert_equal 1, @editor.line_index
    assert_equal 4, @editor.byte_pointer
  end

  def test_autoindent_with_tabs
    @editor.settings.set(:autoindent, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+"\t\thello"])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 7)
    @editor.send(:rvim_insert_newline, nil)
    assert_equal "\t\t", @editor.buffer_of_lines[1].byteslice(0, 2)
  end

  def test_ai_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ai'))
    assert_equal true, @editor.settings.get(:autoindent)
  end
end

class TestLaststatus < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    buf = Rvim::Buffer.new(1, nil); buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf); win.height = 5; win.width = 30; win.row = 0; win.col = 0
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_2_shows_status_row
    out = @screen.send(:render_window, @editor.current_window)
    assert_match(/\e\[7m/, out) # REVERSE_ON for status
  end

  def test_zero_hides_status_row
    @editor.settings.set(:laststatus, 0)
    out = @screen.send(:render_window, @editor.current_window)
    refute_match(/\e\[7m/, out)
  end

  def test_ls_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ls=0'))
    assert_equal 0, @editor.settings.get(:laststatus)
  end
end

class TestNrformats < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def buf(line, byte: 0)
    @editor.instance_variable_set(:@buffer_of_lines, [+line])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, byte)
  end

  def increment(arg: 1)
    @editor.send(:rvim_increment, nil, arg: arg)
  end

  def decrement(arg: 1)
    @editor.send(:rvim_decrement, nil, arg: arg)
  end

  def test_hex_increment
    buf('addr 0x1F', byte: 5)
    increment
    assert_equal 'addr 0x20', @editor.buffer_of_lines[0]
  end

  def test_hex_decrement
    buf('addr 0x10', byte: 5)
    decrement
    assert_equal 'addr 0x0f', @editor.buffer_of_lines[0]
  end

  def test_hex_preserves_width
    buf('val 0x0001', byte: 4)
    increment
    assert_equal 'val 0x0002', @editor.buffer_of_lines[0]
  end

  def test_bin_increment
    buf('flag 0b101', byte: 5)
    increment
    assert_equal 'flag 0b110', @editor.buffer_of_lines[0]
  end

  def test_decimal_still_works
    buf('count 42')
    increment
    assert_equal 'count 43', @editor.buffer_of_lines[0]
  end

  def test_disabling_hex_falls_back_to_decimal
    @editor.settings.set(:nrformats, '')
    buf('addr 0x1F', byte: 5)
    increment
    # With nrformats='' cursor on '0' increments it to 1 (treats '0' as decimal)
    assert_equal 'addr 1x1F', @editor.buffer_of_lines[0]
  end

  def test_nf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nf=hex'))
    assert_equal 'hex', @editor.settings.get(:nrformats)
  end
end
