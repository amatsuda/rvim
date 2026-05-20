# frozen_string_literal: true

require_relative 'test_helper'

# Esc in the :ex / search prompt should cancel and return to normal
# mode. Reline can deliver the byte as either a 1-char String ("\e")
# or as an Integer (27), with various method_symbols (:ed_unassigned,
# :vi_command_mode); we want all those shapes to cancel.

class TestCmdlineEsc < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def enter_ex_and_type(ch_sym_pairs)
    @editor.update(Reline::Key.new(':', :rvim_enter_command_mode, false))
    assert_equal :ex, @editor.instance_variable_get(:@prompt_mode)
    ch_sym_pairs.each do |ch, sym|
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_esc_as_string_cancels
    enter_ex_and_type([['h', :ed_insert], ['i', :ed_insert]])
    @editor.update(Reline::Key.new("\e", :ed_unassigned, false))
    assert_nil @editor.instance_variable_get(:@prompt_mode)
    assert_equal '', @editor.instance_variable_get(:@prompt_buffer)
  end

  def test_esc_as_integer_27_cancels
    # Regression: when Reline delivers Esc as an Integer (byte 27)
    # instead of a String, the case branch in process_prompt_key
    # didn't match "\e" — Esc fell through to the else branch and
    # got appended to the prompt buffer as literal "27".
    enter_ex_and_type([['h', :ed_insert], ['i', :ed_insert]])
    @editor.update(Reline::Key.new(27, :ed_unassigned, false))
    assert_nil @editor.instance_variable_get(:@prompt_mode)
    assert_equal '', @editor.instance_variable_get(:@prompt_buffer)
  end

  def test_esc_as_vi_command_mode_symbol_cancels
    enter_ex_and_type([['h', :ed_insert]])
    @editor.update(Reline::Key.new(27, :vi_command_mode, false))
    assert_nil @editor.instance_variable_get(:@prompt_mode)
  end

  def test_esc_with_nil_char_cancels
    enter_ex_and_type([['h', :ed_insert]])
    @editor.update(Reline::Key.new(nil, :vi_command_mode, false))
    assert_nil @editor.instance_variable_get(:@prompt_mode)
  end

  def test_esc_during_search_prompt_cancels
    @editor.instance_variable_set(:@buffer_of_lines, ['foo', 'bar'])
    @editor.update(Reline::Key.new('/', :rvim_enter_search_forward, false))
    assert_equal :search_forward, @editor.instance_variable_get(:@prompt_mode)
    @editor.update(Reline::Key.new(27, :ed_unassigned, false))
    assert_nil @editor.instance_variable_get(:@prompt_mode)
  end
end
