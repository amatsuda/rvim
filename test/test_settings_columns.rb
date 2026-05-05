# frozen_string_literal: true

require_relative 'test_helper'

class TestColorColumn < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_parse_single_column
    assert_equal [80], @screen.send(:parse_colorcolumns, '80')
  end

  def test_parse_multiple_columns
    assert_equal [80, 100, 120], @screen.send(:parse_colorcolumns, '80,100,120')
  end

  def test_parse_empty_or_invalid
    assert_equal [], @screen.send(:parse_colorcolumns, '')
    assert_equal [], @screen.send(:parse_colorcolumns, ',,,')
  end

  def test_parse_skips_negatives_and_zero
    assert_equal [80], @screen.send(:parse_colorcolumns, '80,0,-5')
  end

  def test_alias_cc_via_set
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cc=80,120'))
    assert_equal '80,120', @editor.settings.get(:colorcolumn)
  end

  def test_render_overlay_emits_at_each_col
    buf = Rvim::Buffer.new(1, nil); buf.lines = [+'hello']
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf); win.height = 5; win.width = 100; win.row = 0; win.col = 0
    out = @screen.send(:render_colorcolumn_overlay, win, 0, 100, [80, 100], 4)
    # 4 rows × 2 columns = 8 highlight blobs
    bg_count = out.scan(Rvim::Highlights.ansi_prefix('ColorColumn')).size
    assert_equal 8, bg_count
  end
end

class TestNumberwidth < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_4
    assert_equal 4, @editor.settings.get(:numberwidth)
  end

  def test_nuw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nuw=6'))
    assert_equal 6, @editor.settings.get(:numberwidth)
  end

  def test_gutter_width_uses_numberwidth_when_number_on
    @editor.settings.set(:number, true)
    @editor.settings.set(:numberwidth, 6)
    buf = Rvim::Buffer.new(1, nil); buf.lines = (1..10).map(&:to_s)
    assert_equal 6, @screen.send(:gutter_width, buf)
  end

  def test_gutter_width_grows_with_more_digits_than_configured
    @editor.settings.set(:number, true)
    @editor.settings.set(:numberwidth, 4)
    buf = Rvim::Buffer.new(1, nil); buf.lines = (1..10000).map(&:to_s)
    # 5 digits + space = 6; numberwidth=4 should grow to 6
    assert @screen.send(:gutter_width, buf) >= 6
  end

  def test_gutter_width_zero_when_no_numbers
    @editor.settings.set(:number, false)
    @editor.settings.set(:relativenumber, false)
    buf = Rvim::Buffer.new(1, nil); buf.lines = ['a']
    assert_equal 0, @screen.send(:gutter_width, buf)
  end
end

class TestSigncolumn < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_auto
    assert_equal 'auto', @editor.settings.get(:signcolumn)
  end

  def test_scl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set scl=yes'))
    assert_equal 'yes', @editor.settings.get(:signcolumn)
  end

  def test_auto_zero_extra_width
    @editor.settings.set(:signcolumn, 'auto')
    assert_equal 0, @screen.send(:sign_column_width)
  end

  def test_yes_reserves_two_columns
    @editor.settings.set(:signcolumn, 'yes')
    assert_equal 2, @screen.send(:sign_column_width)
  end

  def test_no_zero_columns
    @editor.settings.set(:signcolumn, 'no')
    assert_equal 0, @screen.send(:sign_column_width)
  end

  def test_gutter_width_includes_sign_column
    @editor.settings.set(:number, true)
    @editor.settings.set(:numberwidth, 4)
    @editor.settings.set(:signcolumn, 'yes')
    buf = Rvim::Buffer.new(1, nil); buf.lines = (1..10).map(&:to_s)
    width = @screen.send(:gutter_width, buf)
    assert_equal 4 + 2, width # numberwidth + sign column
  end

  def test_gutter_width_only_signs
    @editor.settings.set(:number, false)
    @editor.settings.set(:relativenumber, false)
    @editor.settings.set(:signcolumn, 'yes')
    buf = Rvim::Buffer.new(1, nil); buf.lines = ['a']
    assert_equal 2, @screen.send(:gutter_width, buf)
  end
end

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

class TestStatuscolumnStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:statuscolumn)
  end

  def test_set_statuscolumn
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set statuscolumn=%s%l'))
    assert_equal '%s%l', @editor.settings.get(:statuscolumn)
  end
end
