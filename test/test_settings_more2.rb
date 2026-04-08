# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestCursorColumn < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
    buf = Rvim::Buffer.new(1, nil); buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    @win = Rvim::Window.new(buf); @win.height = 5; @win.width = 30; @win.row = 0; @win.col = 0
    @editor.instance_variable_set(:@windows, [@win])
    @editor.instance_variable_set(:@current_window, @win)
  end

  def test_cursorcolumn_default_off
    assert_equal false, @editor.settings.get(:cursorcolumn)
  end

  def test_cuc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cuc'))
    assert_equal true, @editor.settings.get(:cursorcolumn)
  end

  def test_overlay_emits_cursor_col_on_each_row
    out = @screen.send(:render_cursorcolumn_overlay, @win, 0, 30, false, 4)
    bg_count = out.scan(Rvim::Highlights.ansi_prefix('CursorColumn')).size
    assert_equal 4, bg_count
  end
end

class TestFileformat < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_detects_unix_format
    f = Tempfile.new(['ff_unix', '.txt'])
    f.binmode
    f.write("line1\nline2\nline3\n")
    f.close
    @editor.open(f.path)
    assert_equal 'unix', @editor.current_buffer.fileformat
    assert_equal %w[line1 line2 line3], @editor.buffer_of_lines
  ensure
    f&.unlink
  end

  def test_detects_dos_format
    f = Tempfile.new(['ff_dos', '.txt'])
    f.binmode
    f.write("line1\r\nline2\r\nline3\r\n")
    f.close
    @editor.open(f.path)
    assert_equal 'dos', @editor.current_buffer.fileformat
    assert_equal %w[line1 line2 line3], @editor.buffer_of_lines
  ensure
    f&.unlink
  end

  def test_detects_mac_format
    f = Tempfile.new(['ff_mac', '.txt'])
    f.binmode
    f.write("line1\rline2\rline3\r")
    f.close
    @editor.open(f.path)
    assert_equal 'mac', @editor.current_buffer.fileformat
    assert_equal %w[line1 line2 line3], @editor.buffer_of_lines
  ensure
    f&.unlink
  end

  def test_save_uses_buffer_fileformat_dos
    f = Tempfile.new(['ff_save', '.txt'])
    f.binmode
    f.write("a\nb\n")
    f.close
    @editor.open(f.path)
    @editor.current_buffer.fileformat = 'dos'
    @editor.save
    contents = File.binread(f.path)
    assert_equal "a\r\nb\r\n", contents
  ensure
    f&.unlink
  end

  def test_save_unix_format
    f = Tempfile.new(['ff_save', '.txt'])
    f.binmode
    f.write("a\nb\n")
    f.close
    @editor.open(f.path)
    @editor.current_buffer.fileformat = 'unix'
    @editor.save
    contents = File.binread(f.path)
    assert_equal "a\nb\n", contents
  ensure
    f&.unlink
  end
end

class TestStatuslineFormat < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, %w[line1 line2 line3 line4])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 3)
    buf = Rvim::Buffer.new(1, '/path/to/foo.rb'); buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    @editor.instance_variable_set(:@filepath, '/path/to/foo.rb')
    @win = Rvim::Window.new(buf); @win.width = 80
    @editor.instance_variable_set(:@windows, [@win])
    @editor.instance_variable_set(:@current_window, @win)
  end

  def test_format_filename
    out = Rvim::Statusline.format('%f', @editor, @win, is_current: true)
    assert_equal '/path/to/foo.rb', out
  end

  def test_format_modified_flag
    @editor.modified = true
    out = Rvim::Statusline.format('%m', @editor, @win, is_current: true)
    assert_equal '[+]', out
  end

  def test_format_line_col
    out = Rvim::Statusline.format('%l,%c', @editor, @win, is_current: true)
    assert_equal '2,4', out
  end

  def test_format_total_lines_and_pct
    out = Rvim::Statusline.format('%l/%L %p%%', @editor, @win, is_current: true)
    assert_equal '2/4 50%', out
  end

  def test_format_filetype
    out = Rvim::Statusline.format('%y', @editor, @win, is_current: true)
    assert_equal '[ruby]', out
  end

  def test_format_alignment
    formatted = Rvim::Statusline.format('left%=right', @editor, @win, is_current: true)
    aligned = Rvim::Statusline.align_to_width(formatted, 20)
    assert_equal 'left           right', aligned
  end

  def test_format_literal_percent
    out = Rvim::Statusline.format('100%%', @editor, @win, is_current: true)
    assert_equal '100%', out
  end

  def test_screen_uses_custom_statusline_when_set
    screen = Rvim::Screen.new(@editor)
    @editor.settings.set(:statusline, '%f|%l/%L')
    out = screen.send(:window_status, @win, true)
    assert out.include?('foo.rb')
    assert out.include?('2/4')
  end

  def test_screen_uses_default_when_statusline_empty
    screen = Rvim::Screen.new(@editor)
    out = screen.send(:window_status, @win, true)
    assert out.include?('foo.rb')
    assert out.include?('2,4') # default ruler
  end
end
