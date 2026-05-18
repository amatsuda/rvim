# frozen_string_literal: true

require_relative 'test_helper'

# `*` / `#` / `/foo` highlight every match. The match the cursor
# currently sits inside gets a DIFFERENT style than the others —
# without that, the terminal's text cursor (which inverts the cell)
# disappears against a uniformly-reversed match, making it hard to
# see where you actually are. Matches NeoVim's CurSearch/Search
# split.

class TestCursearchHighlight < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:hlsearch, true)
    @screen = Rvim::Screen.new(@editor)

    # Buffer: "foo bar foo baz foo" — three occurrences of foo.
    @editor.instance_variable_set(:@buffer_of_lines, [+'foo bar foo baz foo'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 8) # on 2nd `foo`
    # Match list: [line, start_byte, end_byte_inclusive]
    @editor.instance_variable_set(:@search_matches,
                                  [[0, 0, 2], [0, 8, 10], [0, 16, 18]])
  end

  CURSEARCH_OPEN = "\e[48;5;220;38;5;232m"
  CURSEARCH_CLOSE = "\e[39;49m"
  REVERSE_ON = "\e[7m"
  REVERSE_OFF = "\e[27m"

  def render(line_text)
    @screen.send(:apply_search_highlight, line_text, 0,
                 @editor.instance_variable_get(:@search_matches), 80)
  end

  def test_cursor_match_uses_distinct_style
    out = render('foo bar foo baz foo')
    # Second `foo` (at 8..10) is current — uses CURSEARCH style.
    assert_match(/#{Regexp.escape(CURSEARCH_OPEN)}foo#{Regexp.escape(CURSEARCH_CLOSE)}/, out)
  end

  def test_other_matches_keep_reverse_video
    out = render('foo bar foo baz foo')
    # First and third use REVERSE — two occurrences of `\e[7mfoo\e[27m`.
    pattern = /#{Regexp.escape(REVERSE_ON)}foo#{Regexp.escape(REVERSE_OFF)}/
    assert_equal 2, out.scan(pattern).size, 'two reversed matches expected'
  end

  def test_cursor_on_different_line_uses_reverse_for_all_matches_here
    # If the cursor's line_index doesn't match this line, NONE of the
    # matches on this line are "current" — they all get REVERSE.
    @editor.instance_variable_set(:@line_index, 99)
    out = render('foo bar foo baz foo')
    pattern = /#{Regexp.escape(REVERSE_ON)}foo#{Regexp.escape(REVERSE_OFF)}/
    assert_equal 3, out.scan(pattern).size
    refute_match(/#{Regexp.escape(CURSEARCH_OPEN)}/, out)
  end

  def test_cursor_at_match_start_boundary_counts_as_current
    @editor.instance_variable_set(:@byte_pointer, 8) # exactly start of 2nd foo
    out = render('foo bar foo baz foo')
    assert_match(/#{Regexp.escape(CURSEARCH_OPEN)}foo#{Regexp.escape(CURSEARCH_CLOSE)}/, out)
  end

  def test_cursor_at_match_end_boundary_counts_as_current
    @editor.instance_variable_set(:@byte_pointer, 10) # last byte of 2nd foo (inclusive)
    out = render('foo bar foo baz foo')
    assert_match(/#{Regexp.escape(CURSEARCH_OPEN)}foo#{Regexp.escape(CURSEARCH_CLOSE)}/, out)
  end

  def test_cursor_between_matches_no_current_highlight
    @editor.instance_variable_set(:@byte_pointer, 4) # on the ` ` after first foo
    out = render('foo bar foo baz foo')
    refute_match(/#{Regexp.escape(CURSEARCH_OPEN)}/, out)
  end
end
