# frozen_string_literal: true

require_relative 'test_helper'

# Unified operator-pending dispatch: d/c/y compose with ANY motion the
# editor dispatches, including rvim-custom motions (}, {, %, n, N, *, #,
# gj/gk) that aren't in Reline's hardcoded VI_MOTIONS set.
class TestOperatorPendingUnified < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def setup_buffer(*lines, line_index: 0, byte_pointer: 0)
    @editor.instance_variable_set(:@buffer_of_lines, lines.map { |l| +l })
    @editor.instance_variable_set(:@line_index, line_index)
    @editor.instance_variable_set(:@byte_pointer, byte_pointer)
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_d_brace_forward_deletes_paragraph_linewise
    setup_buffer('hello', '', 'world')
    send_keys('d', '}')
    assert_equal ['world'], @editor.buffer_of_lines
  end

  def test_c_brace_backward_changes_paragraph
    setup_buffer('a', '', 'b', '', 'c', line_index: 4)
    send_keys('c', '{')
    # Buffer keeps a placeholder empty line where the changed range was.
    refute_equal 'c', @editor.buffer_of_lines.last
    assert_equal :vi_insert, @editor.editing_mode_label
  end

  def test_y_percent_yanks_match_range
    setup_buffer('(hello)', byte_pointer: 0)
    send_keys('y', '%')
    entry = @editor.read_register('"')
    refute_nil entry
    assert_equal '(hello)', entry.text
  end

  def test_dn_deletes_through_next_search_match
    setup_buffer('abc xyz')
    @editor.instance_variable_set(:@search_pattern, 'xyz')
    @editor.instance_variable_set(:@search_direction, :forward)
    @editor.instance_variable_set(:@search_matches, Rvim::Search.scan(@editor.buffer_of_lines, 'xyz'))
    send_keys('d', 'n')
    assert_match(/^xyz/, @editor.buffer_of_lines[0])
  end

  def test_dd_linewise_current_line
    setup_buffer('a', 'b', 'c', line_index: 1)
    send_keys('d', 'd')
    assert_equal ['a', 'c'], @editor.buffer_of_lines
  end

  def test_yy_yanks_current_line
    setup_buffer('the line', line_index: 0)
    send_keys('y', 'y')
    entry = @editor.read_register('"')
    assert_equal 'the line', entry.text
    assert_equal :line, entry.kind
  end

  def test_cc_clears_current_line_and_enters_insert
    setup_buffer('keep', 'replace me', 'keep', line_index: 1)
    send_keys('c', 'c')
    assert_equal '', @editor.buffer_of_lines[1]
    assert_equal :vi_insert, @editor.editing_mode_label
  end

  def test_diw_text_object_still_works
    setup_buffer('abc def', byte_pointer: 4) # on 'd'
    send_keys('d', 'i', 'w')
    assert_equal 'abc ', @editor.buffer_of_lines[0]
  end

  def test_caw_text_object_still_works
    setup_buffer('hello world', byte_pointer: 0)
    send_keys('c', 'a', 'w')
    refute_match(/^hello/, @editor.buffer_of_lines[0])
    assert_equal :vi_insert, @editor.editing_mode_label
  end

  def test_yip_text_object_still_works
    setup_buffer('para1', '', 'para2', line_index: 0)
    send_keys('y', 'i', 'p')
    entry = @editor.read_register('"')
    assert_includes entry.text, 'para1'
  end

  def test_esc_cancels_pending_op
    setup_buffer('untouched')
    send_keys('d', "\e")
    assert_equal 'untouched', @editor.buffer_of_lines[0]
    assert_nil @editor.instance_variable_get(:@rvim_pending_op)
  end

  def test_dw_still_works_after_refactor
    # Regression: the bedrock case that was always working through Reline's
    # built-in operator path. Make sure our bypass didn't break it.
    setup_buffer('abc def', byte_pointer: 0)
    send_keys('d', 'w')
    assert_equal 'def', @editor.buffer_of_lines[0]
  end

  def test_d_paragraph_backward_from_middle
    setup_buffer('a', 'b', '', 'c', line_index: 3, byte_pointer: 0)
    send_keys('d', '{')
    refute_includes @editor.buffer_of_lines, 'c'
    assert_includes @editor.buffer_of_lines, 'b'
  end
end
