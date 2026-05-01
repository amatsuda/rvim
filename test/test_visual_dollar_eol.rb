# frozen_string_literal: true

require_relative 'test_helper'

# Regression: in visual character mode, $ should park the cursor one past
# the last byte (matching NeoVim), not on the last byte. Reline's vi-mode
# dispatch normally clamps cursor back; visual mode is the exception.
class TestVisualDollarEol < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.config.editing_mode = :vi_command
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_dollar_in_visual_char_mode_places_cursor_past_last_char
    send_keys('v', '$')
    assert_equal :char, @editor.visual_mode
    # 'hello' is 5 bytes; cursor should be at byte 5 (the EOL position).
    assert_equal 5, @editor.byte_pointer
  end

  def test_dollar_in_normal_mode_still_clamps_to_last_char
    send_keys('$')
    # Reline's normal-mode behavior: cursor lands on the last char ('o').
    assert_equal 4, @editor.byte_pointer
  end

  def test_dollar_in_visual_block_mode_also_extends_past_eol
    send_keys(0x16.chr) # Ctrl-V
    send_keys('$')
    assert_equal :block, @editor.visual_mode
    assert_equal 5, @editor.byte_pointer
  end

  def test_visual_selection_includes_last_char_after_dollar
    send_keys('v', '$')
    sel = @editor.selection
    refute_nil sel
    # The selection should cover from byte 0 through byte 4 (inclusive).
    assert_equal 0, sel.start_col
    assert_operator sel.end_col, :>=, 4
  end
end
