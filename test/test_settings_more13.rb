# frozen_string_literal: true

require_relative 'test_helper'

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

class TestFormatprg < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:formatprg)
  end

  def test_fp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fp=fmt'))
    assert_equal 'fmt', @editor.settings.get(:formatprg)
  end

  def test_format_uses_formatprg_when_set
    @editor.instance_variable_set(:@buffer_of_lines, [+'banana', +'apple', +'cherry'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:formatprg, 'sort')
    @editor.apply_format_to_lines(0, 2)
    assert_equal %w[apple banana cherry], @editor.buffer_of_lines
  end

  def test_format_falls_back_to_internal_reformat_when_empty
    @editor.settings.set(:textwidth, 12)
    @editor.settings.set(:formatprg, '')
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello world how are you'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.apply_format_to_lines(0, 0)
    assert @editor.buffer_of_lines.size > 1
  end

  def test_format_failure_keeps_buffer
    @editor.instance_variable_set(:@buffer_of_lines, [+'a', +'b', +'c'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:formatprg, 'false')
    @editor.apply_format_to_lines(0, 2)
    assert_equal %w[a b c], @editor.buffer_of_lines
    assert_match(/formatprg/, @editor.status_message.to_s)
  end
end

class TestPasteSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:paste)
  end

  def test_ps_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ps'))
    assert_equal true, @editor.settings.get(:paste)
  end

  def test_pastetoggle_stored
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pt=<F2>'))
    assert_equal '<F2>', @editor.settings.get(:pastetoggle)
  end

  def test_paste_disables_autoindent_on_newline
    @editor.settings.set(:autoindent, true)
    @editor.settings.set(:paste, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+'    indented'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 12)
    @editor.send(:rvim_insert_newline, nil)
    # Paste mode skips the indent carry
    assert_equal ['    indented', ''], @editor.buffer_of_lines
  end

  def test_paste_off_carries_indent
    @editor.settings.set(:autoindent, true)
    @editor.settings.set(:paste, false)
    @editor.instance_variable_set(:@buffer_of_lines, [+'    indented'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 12)
    @editor.send(:rvim_insert_newline, nil)
    assert_equal '    ', @editor.buffer_of_lines[1]
  end
end
