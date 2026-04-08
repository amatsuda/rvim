# frozen_string_literal: true

require_relative 'test_helper'

class TestExpandtab < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
    @editor.instance_variable_set(:@buffer_of_lines, [+''])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_default_tab_inserts_literal_tab
    @editor.settings.set(:expandtab, false)
    @editor.send(:rvim_insert_tab, nil)
    assert_equal "\t", @editor.buffer_of_lines[0]
  end

  def test_expandtab_inserts_spaces
    @editor.settings.set(:expandtab, true)
    @editor.settings.set(:shiftwidth, 4)
    @editor.send(:rvim_insert_tab, nil)
    assert_equal '    ', @editor.buffer_of_lines[0]
    assert_equal 4, @editor.byte_pointer
  end

  def test_expandtab_uses_shiftwidth
    @editor.settings.set(:expandtab, true)
    @editor.settings.set(:shiftwidth, 2)
    @editor.send(:rvim_insert_tab, nil)
    assert_equal '  ', @editor.buffer_of_lines[0]
  end

  def test_alias_et_via_set
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set et'))
    assert_equal true, @editor.settings.get(:expandtab)
  end
end

class TestListchars < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_parse_listchars_defaults
    out = @screen.send(:parse_listchars, '')
    assert_equal '> ', out['tab']
    assert_equal '·', out['trail']
  end

  def test_parse_custom_listchars
    out = @screen.send(:parse_listchars, 'tab:>-,trail:_,eol:$')
    assert_equal '>-', out['tab']
    assert_equal '_', out['trail']
    assert_equal '$', out['eol']
  end

  def test_render_line_uses_listchars
    @editor.settings.set(:list, true)
    @editor.settings.set(:listchars, 'tab:>-,trail:_')
    @editor.settings.set(:tabstop, 4)
    out = @screen.send(:render_line, "\thello   ")
    assert out.include?('>---')
    assert out.include?('___')
  end

  def test_render_line_with_partial_listchars_keeps_default_trail
    @editor.settings.set(:list, true)
    @editor.settings.set(:listchars, 'tab:>-')
    out = @screen.send(:render_line, 'foo   ')
    # parse_listchars seeds defaults; user's spec only overrides 'tab', so
    # 'trail' stays '·' from DEFAULT_LISTCHARS
    assert out.include?('·')
  end

  def test_alias_lcs_via_set
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lcs=tab:>.,trail:_'))
    assert_equal 'tab:>.,trail:_', @editor.settings.get(:listchars)
  end
end

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
