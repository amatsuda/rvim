# frozen_string_literal: true

require_relative 'test_helper'

# Editor#jump_to_diagnostic walks the LSP diagnostic cache and jumps
# the cursor to the next/previous diagnostic relative to its current
# position. Push-jump is used so Ctrl-O comes back.
class TestLspDiagnosticNav < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :diagnostics

    def initialize(diagnostics = [])
      @diagnostics = diagnostics
    end

    def diagnostics_for(_buf)
      @diagnostics
    end

    def pump; end
    def diagnostic_signs(_); {}; end
    def diagnostic_ranges(_); {}; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = ['a = 1', 'b = 2', 'c = 3']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def diag(line, char)
    { range: { start: { line: line, character: char }, end: { line: line, character: char + 1 } },
      severity: 2, message: 'test' }
  end

  def test_jump_to_next_diagnostic_moves_to_next
    @lsp.diagnostics = [diag(0, 0), diag(2, 0)]
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 1)
    @editor.jump_to_diagnostic(:next)
    assert_equal 2, @editor.line_index
    assert_equal 0, @editor.byte_pointer
  end

  def test_jump_to_prev_diagnostic_moves_to_prev
    # Cursor on line 1 (no diagnostic there); :prev should skip back to
    # line 0's diagnostic.
    @lsp.diagnostics = [diag(0, 0), diag(2, 0)]
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.jump_to_diagnostic(:prev)
    assert_equal 0, @editor.line_index
    assert_equal 0, @editor.byte_pointer
  end

  def test_jump_orders_diagnostics_by_line_then_char
    # Diagnostics in non-sorted order in the input array; jump should
    # still pick by sorted (line, char) order.
    @lsp.diagnostics = [diag(2, 0), diag(0, 4), diag(0, 0)]
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.jump_to_diagnostic(:next)
    assert_equal 0, @editor.line_index
    assert_equal 4, @editor.byte_pointer
  end

  def test_no_diagnostics_status_message
    @lsp.diagnostics = []
    @editor.jump_to_diagnostic(:next)
    assert_match(/no diagnostics/, @editor.status_message.to_s)
    assert_equal 0, @editor.line_index
  end

  def test_no_next_when_at_or_past_last
    @lsp.diagnostics = [diag(0, 0), diag(1, 0)]
    @editor.instance_variable_set(:@line_index, 2)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.jump_to_diagnostic(:next)
    assert_match(/no next diagnostic/, @editor.status_message.to_s)
    assert_equal 2, @editor.line_index # unchanged
  end

  def test_no_prev_when_at_or_before_first
    @lsp.diagnostics = [diag(1, 0), diag(2, 0)]
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.jump_to_diagnostic(:prev)
    assert_match(/no previous diagnostic/, @editor.status_message.to_s)
    assert_equal 0, @editor.line_index
  end

  def test_push_jump_records_original_position
    @lsp.diagnostics = [diag(2, 0)]
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 3)
    @editor.jump_to_diagnostic(:next)
    assert_equal [[1, 3]], @editor.jump_list
  end

  def test_jump_skips_diagnostic_at_exact_cursor_position
    # Cursor sitting ON a diagnostic should NOT count as the current
    # one — :next moves to the next, :prev to the previous.
    @lsp.diagnostics = [diag(0, 0), diag(1, 0), diag(2, 0)]
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.jump_to_diagnostic(:next)
    assert_equal 2, @editor.line_index
  end
end
