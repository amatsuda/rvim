# frozen_string_literal: true

require_relative 'test_helper'

# Multi-line clipboard paste in :ex / search prompts should land in the
# prompt buffer as a single line without triggering execute or cancel
# on embedded newlines or escape sequences from bracketed paste.
class TestCmdlinePaste < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+''])
    @paste_state = false
    # Stub the editor-level paste detector so we don't have to fake
    # Reline's IO state globally (which leaks across tests).
    paste_state = -> { @paste_state }
    @editor.define_singleton_method(:pasting_prompt_key?) { paste_state.call }
  end

  def feed(ch, pasting: true)
    @paste_state = pasting
    @editor.send(:process_prompt_key, Reline::Key.new(ch, nil, false))
  end

  def test_pasted_chars_append_to_prompt_buffer
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'')
    %w[h e l l o].each { |c| feed(c) }
    assert_equal 'hello', @editor.prompt_buffer
    assert_equal :ex, @editor.prompt_mode
  end

  def test_newlines_in_paste_are_dropped_not_executed
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'')
    feed('h')
    feed("\n")
    feed('i')
    # \n was dropped instead of triggering execute. Prompt is still open
    # and the chars before/after are concatenated.
    assert_equal :ex, @editor.prompt_mode
    assert_equal 'hi', @editor.prompt_buffer
  end

  def test_carriage_return_in_paste_dropped_not_executed
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'')
    feed('x')
    feed("\r")
    feed('y')
    assert_equal :ex, @editor.prompt_mode
    assert_equal 'xy', @editor.prompt_buffer
  end

  def test_esc_byte_in_paste_does_not_cancel
    # Bare ESC mid-paste enters CSI-consume mode; the following byte is
    # treated as the escape sequence's terminator and also dropped (we
    # can't know without lookahead whether it's `\e[...A` or `\eA`).
    # Crucially, prompt stays open — no cancel.
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'')
    feed('a')
    feed("\e")
    feed('b')
    feed('c')
    assert_equal :ex, @editor.prompt_mode
    # `a` and `c` survive; `\eb` was eaten as an escape sequence.
    assert_equal 'ac', @editor.prompt_buffer
  end

  def test_control_chars_dropped_during_paste_so_cursor_stays_in_sync
    # Without filtering, control bytes would land in the buffer, grow
    # `length`, and push the cursor past the visible end on screen.
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'')
    %W[h e l l o \x01 \x07 \x08].each { |c| feed(c) }
    assert_equal 'hello', @editor.prompt_buffer
  end

  def test_tab_preserved_during_paste
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'')
    feed('a')
    feed("\t")
    feed('b')
    assert_equal "a\tb", @editor.prompt_buffer
  end

  def test_bracketed_paste_start_marker_skipped
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'')
    feed("\e[200~")
    feed('z')
    feed("\e[201~")
    assert_equal 'z', @editor.prompt_buffer
  end

  def test_bracketed_paste_markers_split_across_keys_are_eaten
    # Some terminals/Reline configs deliver `\e[200~` as 6 separate
    # bytes: \e, [, 2, 0, 0, ~. The state machine must eat them all,
    # not just the leading ESC, otherwise `[200~foo[201~` ends up in
    # the buffer literally.
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'')
    keys = ["\e", '[', '2', '0', '0', '~', 'f', 'o', 'o',
            "\e", '[', '2', '0', '1', '~']
    keys.each { |c| feed(c) }
    assert_equal 'foo', @editor.prompt_buffer
  end

  def test_csi_terminator_after_paste_ends_still_eaten
    # The LAST byte (`~`) of the closing \e[201~ marker arrives AFTER
    # Reline reports in_pasting? = false. The CSI-consume state must
    # carry across the boundary so `~` doesn't leak into the buffer.
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'')
    feed("\e",  pasting: true)
    feed('[',   pasting: true)
    feed('2',   pasting: true)
    feed('0',   pasting: true)
    feed('1',   pasting: true)
    feed('~',   pasting: false) # paste has ended; ~ still must be eaten
    assert_equal '', @editor.prompt_buffer
  end

  def test_non_paste_newline_still_executes
    # When NOT pasting, \n should keep its normal "execute" meaning.
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'noh')
    feed("\n", pasting: false)
    # prompt_mode was reset by execute_prompt (hard to assert the exact
    # post-state without setting up a full editor, but we can confirm
    # the prompt closed)
    assert_nil @editor.prompt_mode
  end
end
