# frozen_string_literal: true

require_relative 'test_helper'

# Ctrl-C in vim cancels the current input state — it does NOT quit
# the editor. The render loop's `rescue Interrupt` calls
# editor.handle_ctrl_c_interrupt; this test exercises that method in
# all the input states it should reset.

class TestCtrlCInterrupt < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    buf = Rvim::Buffer.new(1, '/tmp/x')
    buf.lines = ['hello']
    @editor.instance_variable_set(:@buffer_of_lines, buf.lines)
    @editor.instance_variable_set(:@current_buffer, buf)
  end

  def test_does_not_quit_the_editor
    @editor.handle_ctrl_c_interrupt
    refute @editor.quit?
  end

  # ----- status message UX (matches NeoVim) -----
  #
  # Resting normal mode → hint. Anywhere else (insert, visual,
  # command-line prompt, pending op) → silent exit, no message.

  def test_resting_normal_mode_shows_help_hint
    # Editor starts in :vi_command, no pending state.
    @editor.handle_ctrl_c_interrupt
    assert_match(/Type :q to quit/, @editor.status_message.to_s)
  end

  def test_insert_mode_exit_is_silent
    @editor.config.editing_mode = :vi_insert
    @editor.handle_ctrl_c_interrupt
    refute_equal :vi_insert, @editor.send(:editing_mode_label)
    assert_nil @editor.status_message
  end

  def test_insert_at_end_of_line_clamps_cursor_back_onto_last_char
    # Buffer is 'hello' (5 bytes). Insert-mode cursor can sit at
    # byte_pointer=5 (one past `o`); leaving insert via Ctrl-C
    # should clamp to 4 so the box cursor lands on `o`, matching
    # what Esc does.
    @editor.config.editing_mode = :vi_insert
    @editor.instance_variable_set(:@byte_pointer, 5)
    @editor.handle_ctrl_c_interrupt
    assert_equal 4, @editor.byte_pointer
  end

  def test_insert_mid_line_leaves_cursor_in_place
    @editor.config.editing_mode = :vi_insert
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.handle_ctrl_c_interrupt
    assert_equal 2, @editor.byte_pointer
  end

  def test_insert_on_empty_line_clamps_to_zero
    @editor.buffer_of_lines[0] = ''
    @editor.config.editing_mode = :vi_insert
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.handle_ctrl_c_interrupt
    assert_equal 0, @editor.byte_pointer
  end

  def test_visual_mode_exit_is_silent
    @editor.instance_variable_set(:@visual_mode, :char)
    @editor.instance_variable_set(:@visual_anchor, [0, 0])
    @editor.handle_ctrl_c_interrupt
    assert_nil @editor.visual_mode
    assert_nil @editor.status_message
  end

  def test_command_line_prompt_exit_is_silent
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'q')
    @editor.handle_ctrl_c_interrupt
    assert_nil @editor.prompt_mode
    assert_nil @editor.status_message
  end

  def test_pending_operator_cancel_still_shows_hint
    # A pending operator (`d` waiting for motion) is still normal
    # mode — clearing it doesn't suppress the "Type :q to quit" hint.
    @editor.instance_variable_set(:@rvim_pending_op, :delete)
    @editor.handle_ctrl_c_interrupt
    assert_match(/Type :q to quit/, @editor.status_message.to_s)
  end

  def test_cancels_pending_operator
    @editor.instance_variable_set(:@rvim_pending_op, :delete)
    @editor.instance_variable_set(:@rvim_pending_op_count, 3)
    @editor.handle_ctrl_c_interrupt
    assert_nil @editor.instance_variable_get(:@rvim_pending_op)
    assert_equal 1, @editor.instance_variable_get(:@rvim_pending_op_count)
  end

  def test_cancels_text_object_pending
    @editor.instance_variable_set(:@rvim_text_object_pending, :around)
    @editor.handle_ctrl_c_interrupt
    assert_nil @editor.instance_variable_get(:@rvim_text_object_pending)
  end

  def test_cancels_waiting_proc
    @editor.instance_variable_set(:@waiting_proc, ->(*) {})
    @editor.handle_ctrl_c_interrupt
    assert_nil @editor.instance_variable_get(:@waiting_proc)
  end

  def test_drops_out_of_insert_mode
    @editor.config.editing_mode = :vi_insert
    @editor.handle_ctrl_c_interrupt
    refute_equal :vi_insert, @editor.send(:editing_mode_label)
  end

  def test_exits_visual_mode
    @editor.instance_variable_set(:@visual_mode, :char)
    @editor.instance_variable_set(:@visual_anchor, [0, 0])
    @editor.handle_ctrl_c_interrupt
    assert_nil @editor.visual_mode
  end

  def test_clears_open_prompt
    @editor.instance_variable_set(:@prompt_mode, :ex)
    @editor.instance_variable_set(:@prompt_buffer, +'some text')
    @editor.handle_ctrl_c_interrupt
    assert_nil @editor.prompt_mode
    assert_equal '', @editor.prompt_buffer
  end

  def test_dismisses_hover_signature_diagnostic_popups
    @editor.instance_variable_set(:@hover_popup, :stale)
    @editor.instance_variable_set(:@signature_popup, :stale)
    @editor.instance_variable_set(:@diagnostic_popup, :stale)
    @editor.handle_ctrl_c_interrupt
    assert_nil @editor.hover_popup
    assert_nil @editor.signature_popup
    assert_nil @editor.diagnostic_popup
  end

  def test_cancels_completion_session
    @editor.instance_variable_set(:@completion_active, true)
    @editor.instance_variable_set(:@completion_candidates, %w[a b])
    @editor.handle_ctrl_c_interrupt
    refute @editor.instance_variable_get(:@completion_active)
    assert_empty @editor.instance_variable_get(:@completion_candidates)
  end

  def test_handle_signal_does_not_set_quit
    # Reline's SIGINT trap sets @interrupted; handle_signal raises
    # Interrupt so the render loop's rescue runs. Critically it must
    # NOT set @quit — otherwise the loop breaks before the rescue
    # can clear input state, exiting the editor on Ctrl-C.
    @editor.instance_variable_set(:@interrupted, true)
    assert_raise(Interrupt) { @editor.handle_signal }
    refute @editor.quit?, 'handle_signal must never set @quit'
  end
end
