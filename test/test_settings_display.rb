# frozen_string_literal: true

require_relative 'test_helper'

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

class TestShowbreak < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:showbreak)
  end

  def test_sbr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sbr=>>'))
    assert_equal '>>', @editor.settings.get(:showbreak)
  end

  def test_renders_at_continuation
    @editor.settings.set(:showbreak, '↪ ')
    @editor.settings.set(:wrap, true)
    long = 'A' * 30
    @editor.instance_variable_set(:@buffer_of_lines, [long])
    buf = Rvim::Buffer.new(1, nil); buf.lines = [long]
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf); win.row = 0; win.col = 0; win.width = 12; win.height = 5
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)

    out = @screen.send(:render_window, win)
    # Continuation segments should include the showbreak marker
    assert_match(/↪ /, out)
  end

  def test_no_marker_on_first_segment
    @editor.settings.set(:showbreak, '>>>')
    @editor.settings.set(:wrap, true)
    @editor.instance_variable_set(:@buffer_of_lines, ['short'])
    buf = Rvim::Buffer.new(1, nil); buf.lines = ['short']
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf); win.row = 0; win.col = 0; win.width = 80; win.height = 5
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)

    out = @screen.send(:render_window, win)
    refute_match(/>>>/, out)
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

class TestConceallevelStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:conceallevel)
  end

  def test_cole_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cole=2'))
    assert_equal 2, @editor.settings.get(:conceallevel)
  end
end

class TestConcealcursorStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:concealcursor)
  end

  def test_cocu_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cocu=nv'))
    assert_equal 'nv', @editor.settings.get(:concealcursor)
  end
end

class TestBreakatStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_punct
    assert_match(/[!@*]/, @editor.settings.get(:breakat))
  end

  def test_brk_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set brk=\ \t-'))
    refute_nil @editor.settings.get(:breakat)
  end
end

class TestDisplayStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_lastline
    assert_equal 'lastline', @editor.settings.get(:display)
  end

  def test_dy_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set dy=truncate'))
    assert_equal 'truncate', @editor.settings.get(:display)
  end
end

class TestFillcharsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:fillchars)
  end

  def test_fcs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fcs=vert:|,fold:-'))
    assert_equal 'vert:|,fold:-', @editor.settings.get(:fillchars)
  end
end

class TestLazyredrawSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @rendered = 0
    fake = Object.new
    counter = ->(*) { @rendered += 1 }
    fake.define_singleton_method(:render) { counter.call }
    @editor.instance_variable_set(:@screen, fake)
  end

  def test_default_renders_during_replay
    @editor.instance_variable_set(:@replaying, true)
    @editor.render
    assert_equal 1, @rendered
  end

  def test_lazyredraw_skips_render_during_replay
    @editor.settings.set(:lazyredraw, true)
    @editor.instance_variable_set(:@replaying, true)
    @editor.render
    assert_equal 0, @rendered
  end

  def test_lazyredraw_renders_when_not_replaying
    @editor.settings.set(:lazyredraw, true)
    @editor.instance_variable_set(:@replaying, false)
    @editor.render
    assert_equal 1, @rendered
  end
end

class TestSidescrollStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:sidescroll)
  end

  def test_ss_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ss=10'))
    assert_equal 10, @editor.settings.get(:sidescroll)
  end
end

class TestSmoothscrollStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:smoothscroll)
  end

  def test_set_smoothscroll
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set smoothscroll'))
    assert_equal true, @editor.settings.get(:smoothscroll)
  end
end

class TestLinebreak < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_breaks_at_width
    @editor.settings.set(:linebreak, false)
    out = @screen.send(:split_line_segments, 'hello world how are you doing', 12)
    # First segment is exactly 12 chars; word may be split mid-way
    assert_equal 12, out[0][1].length
  end

  def test_linebreak_on_breaks_at_word
    @editor.settings.set(:linebreak, true)
    out = @screen.send(:split_line_segments, 'hello world how are you', 12)
    # 'hello world ' (12 chars with trailing space ends at word boundary)
    assert_equal 'hello world ', out[0][1]
    assert_equal 'how are you', out[1][1]
  end

  def test_linebreak_lbr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lbr'))
    assert_equal true, @editor.settings.get(:linebreak)
  end

  def test_linebreak_falls_through_for_unbreakable
    @editor.settings.set(:linebreak, true)
    # No spaces: falls through to default char-width split
    out = @screen.send(:split_line_segments, 'aaaaaaaaaaaaaaaaaaaa', 5)
    assert_equal 4, out.size # 20 chars / 5 = 4 segments
    out.each { |_, seg| assert_equal 5, seg.length }
  end
end

class TestScrolljump < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, (1..100).map { |i| "line #{i}".dup })
    buf = Rvim::Buffer.new(1, nil); buf.lines = @editor.buffer_of_lines
    @editor.instance_variable_set(:@current_buffer, buf)
    @win = Rvim::Window.new(buf); @win.height = 21; @win.row = 0; @win.col = 0
    @editor.instance_variable_set(:@windows, [@win])
    @editor.instance_variable_set(:@current_window, @win)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_one_minimal_scroll
    @editor.settings.set(:scrolljump, 1)
    @editor.instance_variable_set(:@line_index, 21)
    @win.scroll_top = 0
    @screen.send(:adjust_window_scroll, @win, 20)
    assert_equal 2, @win.scroll_top
  end

  def test_scrolljump_larger_jump
    @editor.settings.set(:scrolljump, 5)
    @editor.instance_variable_set(:@line_index, 21)
    @win.scroll_top = 0
    @screen.send(:adjust_window_scroll, @win, 20)
    # Min jump 5 → scroll_top becomes 5 instead of 2
    assert_equal 5, @win.scroll_top
  end

  def test_scrolljump_does_not_overshoot_when_cursor_far_below
    @editor.settings.set(:scrolljump, 3)
    @editor.instance_variable_set(:@line_index, 50)
    @win.scroll_top = 0
    @screen.send(:adjust_window_scroll, @win, 20)
    # Cursor needs to be visible — scroll_top must be at least 31
    # min jump of 3 from 0 → 3, but cursor at 50 needs scroll_top >= 31
    assert_equal 31, @win.scroll_top
  end

  def test_sj_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sj=10'))
    assert_equal 10, @editor.settings.get(:scrolljump)
  end
end
