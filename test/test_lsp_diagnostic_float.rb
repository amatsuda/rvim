# frozen_string_literal: true

require_relative 'test_helper'

# When the cursor sits inside a diagnostic-underlined range, a small
# floating popup shows the full diagnostic message. The lookup is
# purely local (already-cached diagnostics) so the popup is cheap
# enough to refresh on every render-loop tick.

class TestEditorDiagnosticFloat < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :diags

    def initialize(diags = [])
      @diags = diags
    end

    def diagnostics_for(_buf); @diags; end
    def flush_changes(_buf); false; end
    def maybe_pull_diagnostics(_buf); false; end
    def maybe_pull_inlay_hints(_buf); false; end
    def maybe_pull_document_highlight(_buf); false; end
    def pending_for?(_); false; end
    def pump; end
    def diagnostic_signs(_); {}; end
    def diagnostic_ranges(_); {}; end
    def document_highlights_by_line(_); {}; end
    def inlay_hints_by_line(_); {}; end
  end

  def diag(line:, sc:, ec:, severity: 2, message: 'oops', source: nil)
    h = {
      range: { start: { line: line, character: sc }, end: { line: line, character: ec } },
      severity: severity,
      message: message,
    }
    h[:source] = source if source
    h
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @editor.settings.set(:lsp_diagnostic_float, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = ['x = 1', 'unused = 2']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  # ----- diagnostics_at_cursor (private; private_send) -----

  def test_returns_empty_when_cursor_outside_any_range
    @lsp.diags = [diag(line: 1, sc: 0, ec: 6)]
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    assert_empty @editor.send(:diagnostics_at_cursor, @buf)
  end

  def test_returns_diagnostic_when_cursor_inside_range
    @lsp.diags = [diag(line: 0, sc: 0, ec: 5)]
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
    out = @editor.send(:diagnostics_at_cursor, @buf)
    assert_equal 1, out.size
  end

  def test_returns_diagnostic_at_start_boundary_but_not_end
    # LSP ranges are start-inclusive, end-exclusive.
    @lsp.diags = [diag(line: 0, sc: 2, ec: 5)]
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
    refute_empty @editor.send(:diagnostics_at_cursor, @buf), 'start boundary should match'
    @editor.instance_variable_set(:@byte_pointer, 5)
    assert_empty @editor.send(:diagnostics_at_cursor, @buf), 'end boundary should not match'
  end

  def test_zero_width_range_matches_single_column
    # Some servers emit ranges with start == end pointing AT a column;
    # those should still match when the cursor is on that column.
    @lsp.diags = [diag(line: 0, sc: 3, ec: 3)]
    @editor.instance_variable_set(:@byte_pointer, 3)
    refute_empty @editor.send(:diagnostics_at_cursor, @buf)
    @editor.instance_variable_set(:@byte_pointer, 4)
    assert_empty @editor.send(:diagnostics_at_cursor, @buf)
  end

  def test_returns_multiple_diagnostics_when_ranges_overlap_at_cursor
    @lsp.diags = [
      diag(line: 0, sc: 0, ec: 5, message: 'one'),
      diag(line: 0, sc: 2, ec: 4, message: 'two'),
    ]
    @editor.instance_variable_set(:@byte_pointer, 3)
    assert_equal 2, @editor.send(:diagnostics_at_cursor, @buf).size
  end

  # ----- update_diagnostic_popup_for_cursor -----

  def test_no_popup_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    @lsp.diags = [diag(line: 0, sc: 0, ec: 5)]
    @editor.update_diagnostic_popup_for_cursor
    assert_nil @editor.diagnostic_popup
  end

  def test_no_popup_when_float_setting_disabled
    @editor.settings.set(:lsp_diagnostic_float, false)
    @lsp.diags = [diag(line: 0, sc: 0, ec: 5)]
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.update_diagnostic_popup_for_cursor
    assert_nil @editor.diagnostic_popup
  end

  def test_popup_opens_with_message_and_severity_prefix
    @lsp.diags = [diag(line: 0, sc: 0, ec: 5, severity: 2, message: 'Unused variable')]
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.update_diagnostic_popup_for_cursor
    refute_nil @editor.diagnostic_popup
    contents = @editor.diagnostic_popup.contents
    assert_equal 1, contents.size
    assert_match(/\[W\]/, contents[0])
    assert_match(/Unused variable/, contents[0])
  end

  def test_popup_includes_source_in_brackets_when_present
    @lsp.diags = [diag(line: 0, sc: 0, ec: 5, source: 'rubocop', message: 'bad')]
    @editor.instance_variable_set(:@byte_pointer, 1)
    @editor.update_diagnostic_popup_for_cursor
    assert_match(/\(rubocop\)/, @editor.diagnostic_popup.contents[0])
  end

  def test_multiline_message_is_split_with_indent
    @lsp.diags = [diag(line: 0, sc: 0, ec: 5, message: "first\nsecond\nthird")]
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.update_diagnostic_popup_for_cursor
    rows = @editor.diagnostic_popup.contents
    assert_equal 3, rows.size
    assert_match(/first/, rows[0])
    assert_match(/\A {4}second/, rows[1])
    assert_match(/\A {4}third/, rows[2])
  end

  def test_popup_dismisses_when_cursor_leaves_range
    @lsp.diags = [diag(line: 0, sc: 0, ec: 5)]
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.update_diagnostic_popup_for_cursor
    refute_nil @editor.diagnostic_popup
    @editor.instance_variable_set(:@byte_pointer, 7)
    @editor.update_diagnostic_popup_for_cursor
    assert_nil @editor.diagnostic_popup
  end

  # ----- lsp_show_diagnostic_float (manual trigger) -----

  def test_manual_trigger_returns_false_when_nothing_under_cursor
    @lsp.diags = [diag(line: 1, sc: 0, ec: 5)]
    @editor.instance_variable_set(:@line_index, 0)
    refute @editor.lsp_show_diagnostic_float
  end

  def test_manual_trigger_returns_true_and_sets_popup
    @lsp.diags = [diag(line: 0, sc: 0, ec: 5)]
    @editor.instance_variable_set(:@byte_pointer, 1)
    assert @editor.lsp_show_diagnostic_float
    refute_nil @editor.diagnostic_popup
  end
end
