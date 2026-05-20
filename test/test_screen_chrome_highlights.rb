# frozen_string_literal: true

require_relative 'test_helper'

# The chrome (line numbers, statusline, tabline, ~ markers, vertical
# split bars) used to paint with hardcoded SGR escapes (DIM/REVERSE).
# Now each piece consults a named highlight group on editor.hl_groups,
# so colorschemes like tokyonight.nvim can theme the whole editor —
# not just syntax highlighting.

class TestScreenChromeHighlights < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'foo'])
    @screen = Rvim::Screen.new(@editor)
  end

  def test_hl_helper_wraps_text_with_group_pair
    @editor.hl_groups.define('TestGroup', 'fg' => '#ff0000')
    out = @screen.hl('TestGroup', 'hello')
    assert_match(/38;2;255;0;0/, out)
    assert out.include?('hello'), "expected text in output: #{out.inspect}"
  end

  def test_hl_helper_returns_plain_text_when_group_unset
    @editor.hl_groups.send(:initialize) # reset to defaults
    assert_equal 'plain', @screen.hl('Nonexistent', 'plain')
  end

  def test_hl_helper_returns_plain_text_when_group_is_no_op
    # Groups like Normal default to empty open/close so the unstyled
    # editor doesn't emit unnecessary escapes.
    @editor.hl_groups.define('NoOp', {})
    assert_equal 'plain', @screen.hl('NoOp', 'plain')
  end

  def test_endofbuffer_marker_uses_hl_group
    @editor.hl_groups.define('EndOfBuffer', 'fg' => '#abcdef')
    out = @screen.send(:hl, 'EndOfBuffer', '~')
    assert_match(/38;2;171;205;239/, out)
    assert out.include?('~')
  end

  def test_linenr_group_used_for_line_numbers
    @editor.hl_groups.define('LineNr', 'fg' => '#404040')
    gw = 4
    out = @screen.send(:gutter_text, 0, 5, 10, gw, true, sign_w: 0)
    assert_match(/38;2;64;64;64/, out, "expected LineNr SGR in gutter: #{out.inspect}")
  end

  def test_cursorlinenr_group_used_for_cursor_line
    @editor.hl_groups.define('LineNr',       'fg' => '#404040')
    @editor.hl_groups.define('CursorLineNr', 'fg' => '#ffff00', 'bold' => true)
    out = @screen.send(:gutter_text, 5, 5, 10, 4, true, sign_w: 0)
    refute_match(/38;2;64;64;64/, out, "expected LineNr NOT used on cursor row")
    assert_match(/38;2;255;255;0/, out, "expected CursorLineNr SGR: #{out.inspect}")
  end

  def test_tabline_uses_tabline_groups
    @editor.hl_groups.define('TabLine',    'fg' => '#222222')
    @editor.hl_groups.define('TabLineSel', 'fg' => '#ff8800')
    # Stub minimal tab objects rather than driving :tabnew.
    fake_tab = Struct.new(:display_name).new('one')
    fake_two = Struct.new(:display_name).new('two')
    @editor.define_singleton_method(:tabs) { [fake_tab, fake_two] }
    @editor.define_singleton_method(:current_tab_index) { 0 }
    out = @screen.send(:render_tabline)
    assert_match(/38;2;34;34;34/, out, "expected TabLine SGR")
    assert_match(/38;2;255;136;0/, out, "expected TabLineSel SGR")
  end

  def test_vertical_separator_uses_winseparator_group
    @editor.hl_groups.define('WinSeparator', 'fg' => '#506070')
    bar = @screen.send(:hl, 'WinSeparator', '│')
    assert_match(/38;2;80;96;112/, bar)
  end

  def test_syntax_picks_up_colorscheme_overrides
    # Regression: Ruby constants stayed dim/blue under tokyonight
    # because the syntax painter only consulted the legacy
    # Rvim::Highlights registry. Colorscheme plugins write to
    # editor.hl_groups via nvim_set_hl — that needs to win.
    @editor.hl_groups.define('Constant', 'fg' => '#ff9e64')
    pre, suf = @screen.send(:syntax_sgr_for, 'Constant')
    assert_match(/38;2;255;158;100/, pre)
    refute pre.empty?
    refute suf.empty?
  end

  def test_syntax_falls_back_to_legacy_when_group_unset
    # An rvim-only group that the colorscheme didn't touch should
    # still come from Rvim::Highlights so existing themes don't
    # regress.
    pre, _suf = @screen.send(:syntax_sgr_for, 'Symbol')
    refute pre.empty?, 'expected legacy fallback for Symbol'
  end

  def test_chrome_defaults_present
    %w[Normal LineNr CursorLineNr StatusLine StatusLineNC
       TabLine TabLineSel EndOfBuffer VertSplit WinSeparator
       SignColumn FoldColumn Folded].each do |g|
      assert_not_nil @editor.hl_groups.lookup(g), "expected default for #{g}"
    end
  end
end
