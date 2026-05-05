# frozen_string_literal: true

require_relative 'test_helper'

class TestShortmessStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_value
    assert_equal 'filnxtToOS', @editor.settings.get(:shortmess)
  end

  def test_shm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set shm=at'))
    assert_equal 'at', @editor.settings.get(:shortmess)
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

class TestCmdheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one
    assert_equal 1, @editor.settings.get(:cmdheight)
  end

  def test_ch_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ch=2'))
    assert_equal 2, @editor.settings.get(:cmdheight)
  end
end

class TestReportStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_two
    assert_equal 2, @editor.settings.get(:report)
  end

  def test_set_report
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set report=10'))
    assert_equal 10, @editor.settings.get(:report)
  end
end

class TestCmdwinheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_seven
    assert_equal 7, @editor.settings.get(:cmdwinheight)
  end

  def test_cwh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cwh=10'))
    assert_equal 10, @editor.settings.get(:cmdwinheight)
  end
end

class TestTablineStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:tabline)
  end

  def test_tal_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tal=%!MyTabLine()'))
    assert_equal '%!MyTabLine()', @editor.settings.get(:tabline)
  end
end

class TestVerboseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:verbose)
  end

  def test_vbs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vbs=9'))
    assert_equal 9, @editor.settings.get(:verbose)
  end
end

class TestShowmodeSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    buf = Rvim::Buffer.new(1, nil); buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    @win = Rvim::Window.new(buf)
    @editor.instance_variable_set(:@current_window, @win)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_showmode_on_includes_mode_label
    @editor.settings.set(:showmode, true)
    out = @screen.send(:window_status, @win, true)
    assert_match(/\[(Normal|Visual|Insert)\]/, out)
  end

  def test_showmode_off_omits_mode_label
    @editor.settings.set(:showmode, false)
    out = @screen.send(:window_status, @win, true)
    refute_match(/\[(Normal|Visual|Insert)\]/, out)
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

class TestTitle < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:title)
  end

  def test_render_title_with_filepath
    @editor.instance_variable_set(:@filepath, '/path/to/foo.rb')
    out = @screen.send(:render_title)
    assert_equal "\e]0;foo.rb - rvim\a", out
  end

  def test_render_title_with_no_filepath
    out = @screen.send(:render_title)
    assert_equal "\e]0;[No Name] - rvim\a", out
  end

  def test_render_title_with_custom_titlestring
    @editor.settings.set(:titlestring, 'MyEditor')
    out = @screen.send(:render_title)
    assert_equal "\e]0;MyEditor\a", out
  end

  def test_tl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tl'))
    assert_equal true, @editor.settings.get(:title)
  end
end

class TestShowtabline < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
    # Build a tabs list with two tabs so showtabline=1 should show
    buf = Rvim::Buffer.new(1, nil)
    win = Rvim::Window.new(buf)
    tab1 = Rvim::Tab.new(win)
    tab2 = Rvim::Tab.new(Rvim::Window.new(buf))
    @editor.instance_variable_set(:@tabs, [tab1, tab2])
  end

  def test_default_1_shows_only_when_multi_tab
    @editor.settings.set(:showtabline, 1)
    assert_equal 1, @screen.send(:tabline_height)
    @editor.instance_variable_set(:@tabs, [@editor.tabs.first])
    assert_equal 0, @screen.send(:tabline_height)
  end

  def test_zero_never_shows
    @editor.settings.set(:showtabline, 0)
    assert_equal 0, @screen.send(:tabline_height)
  end

  def test_two_always_shows
    @editor.settings.set(:showtabline, 2)
    @editor.instance_variable_set(:@tabs, [@editor.tabs.first])
    assert_equal 1, @screen.send(:tabline_height)
  end

  def test_stal_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set stal=2'))
    assert_equal 2, @editor.settings.get(:showtabline)
  end
end
