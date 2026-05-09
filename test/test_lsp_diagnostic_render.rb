# frozen_string_literal: true

require_relative 'test_helper'

# Render-side tests for LSP diagnostic display: signcolumn glyphs and
# inline underline. Builds a fake Lsp::Manager that returns canned
# diagnostics so the renderer is exercised in isolation.
class TestLspDiagnosticRender < Test::Unit::TestCase
  class FakeLsp
    def initialize(signs: {}, ranges: {}, diagnostics: [])
      @signs = signs
      @ranges = ranges
      @diagnostics = diagnostics
    end

    def diagnostic_signs(_buf) = @signs
    def diagnostic_ranges(_buf) = @ranges
    def diagnostics_for(_buf) = @diagnostics
    def pump = nil
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def make_buffer(lines)
    buf = Rvim::Buffer.new(1, nil)
    buf.lines = lines
    @editor.instance_variable_set(:@buffer_of_lines, lines)
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf)
    win.row = 0; win.col = 0; win.width = 80; win.height = 5
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)
    [buf, win]
  end

  def install_fake_lsp(signs: {}, ranges: {}, diagnostics: [])
    fake = FakeLsp.new(signs: signs, ranges: ranges, diagnostics: diagnostics)
    @editor.instance_variable_set(:@lsp, fake)
    fake
  end

  # ----- diagnostic_signs / diagnostic_ranges (Lsp::Manager) -----

  def test_diagnostic_signs_collapses_to_most_severe_per_line
    manager = Rvim::Lsp::Manager.new(@editor)
    buf, = make_buffer(['x = 1'])
    fake_client = Object.new
    diag_warning = { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } }, severity: 2 }
    diag_error = { range: { start: { line: 0, character: 2 }, end: { line: 0, character: 3 } }, severity: 1 }
    fake_client.define_singleton_method(:diagnostics) { { 'file:///x' => [diag_warning, diag_error] } }
    manager.instance_variable_set(:@clients, { ruby: fake_client })
    manager.define_singleton_method(:filetype_for) { |_| :ruby }
    manager.define_singleton_method(:buffer_uri) { |_| 'file:///x' }
    signs = manager.diagnostic_signs(buf)
    assert_equal 1, signs[0]
  end

  def test_diagnostic_ranges_returns_one_entry_per_diagnostic_sorted_by_start
    manager = Rvim::Lsp::Manager.new(@editor)
    buf, = make_buffer(['x = 1; y = 2'])
    diag_b = { range: { start: { line: 0, character: 7 }, end: { line: 0, character: 8 } }, severity: 2 }
    diag_a = { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } }, severity: 1 }
    fake_client = Object.new
    fake_client.define_singleton_method(:diagnostics) { { 'file:///x' => [diag_b, diag_a] } }
    manager.instance_variable_set(:@clients, { ruby: fake_client })
    manager.define_singleton_method(:filetype_for) { |_| :ruby }
    manager.define_singleton_method(:buffer_uri) { |_| 'file:///x' }
    ranges = manager.diagnostic_ranges(buf)
    line0 = ranges[0]
    assert_equal 2, line0.size
    assert_equal 0, line0[0][:first_col]
    assert_equal 7, line0[1][:first_col]
  end

  # ----- sign_column_width_for -----

  def test_sign_column_width_with_signcolumn_yes
    @editor.settings.set(:signcolumn, 'yes')
    install_fake_lsp(signs: {})
    buf, = make_buffer(['ok'])
    assert_equal 2, @screen.send(:sign_column_width_for, buf)
  end

  def test_sign_column_width_auto_with_no_diagnostics
    @editor.settings.set(:signcolumn, 'auto')
    @editor.settings.set(:lsp_enabled, true)
    install_fake_lsp(signs: {})
    buf, = make_buffer(['ok'])
    assert_equal 0, @screen.send(:sign_column_width_for, buf)
  end

  def test_sign_column_width_auto_with_diagnostics
    @editor.settings.set(:signcolumn, 'auto')
    @editor.settings.set(:lsp_enabled, true)
    install_fake_lsp(signs: { 0 => 1 })
    buf, = make_buffer(['ok'])
    assert_equal 2, @screen.send(:sign_column_width_for, buf)
  end

  def test_sign_column_width_no_when_disabled
    @editor.settings.set(:signcolumn, 'no')
    install_fake_lsp(signs: { 0 => 1 })
    buf, = make_buffer(['ok'])
    assert_equal 0, @screen.send(:sign_column_width_for, buf)
  end

  # ----- gutter_text -----

  def test_gutter_text_renders_severity_glyph_and_color
    @editor.settings.set(:number, true)
    out = @screen.send(:gutter_text, 0, 0, 1, 5, true, sign: 1, sign_w: 2)
    assert_match(/E /, out)
    assert_match(/\e\[38;5;196m/, out)
  end

  def test_gutter_text_pads_sign_column_when_no_sign
    @editor.settings.set(:number, true)
    out = @screen.send(:gutter_text, 0, 0, 1, 5, true, sign: nil, sign_w: 2)
    refute_match(/\e\[38;5;\d+m/, out)
  end

  # ----- apply_diagnostic_overlay -----

  def test_overlay_underlines_diagnostic_byte_range
    diags = [{ first_col: 0, last_col: 5, severity: 2 }]
    out = @screen.send(:apply_diagnostic_overlay, 'hello world', diags)
    assert_match(/\e\[4;38;5;214mhello\e\[24;39m/, out)
  end

  def test_overlay_with_no_diagnostics_returns_plain
    out = @screen.send(:apply_diagnostic_overlay, 'hello', [])
    refute_match(/\e\[4;38;5;\d+m/, out)
  end

  def test_overlay_handles_multiple_ranges
    # 'abc def ghi' — byte positions: abc=0..3, def=4..7, ghi=8..11
    diags = [
      { first_col: 0, last_col: 3, severity: 1 },
      { first_col: 4, last_col: 7, severity: 4 },
    ]
    out = @screen.send(:apply_diagnostic_overlay, 'abc def ghi', diags)
    assert_match(/\e\[4;38;5;196mabc\e\[24;39m/, out)
    assert_match(/\e\[4;38;5;245mdef\e\[24;39m/, out)
  end

  def test_overlay_skips_existing_sgr_when_counting_bytes
    # Pre-highlighted "x" wrapped in syntax color: \e[31mx\e[39m, plus " = 1".
    # Diagnostic on byte 0 of original (the 'x') should wrap correctly without
    # being broken by the embedded SGR codes.
    pre = "\e[31mx\e[39m = 1"
    diags = [{ first_col: 0, last_col: 1, severity: 2 }]
    out = @screen.send(:apply_diagnostic_overlay, pre, diags)
    # The diagnostic SGR opens before content, closes after the 'x'.
    assert_match(/\e\[4;38;5;214m/, out)
    assert_match(/\e\[24;39m/, out)
    # Non-x content remains intact: the rendered output still ends with " = 1".
    assert out.end_with?(' = 1')
  end

  def test_overlay_safe_with_multibyte_range
    # Multi-byte char 'あ' is 3 bytes. Range covers a..end-of-あ.
    line = 'aあい'
    diags = [{ first_col: 0, last_col: 1 + 3, severity: 1 }]
    assert_nothing_raised do
      out = @screen.send(:apply_diagnostic_overlay, line, diags)
      assert out.include?('a')
      assert out.include?('あ')
    end
  end

  # ----- end-to-end render_window -----

  def test_render_window_includes_sign_glyph_and_underline
    @editor.settings.set(:lsp_enabled, true)
    @editor.settings.set(:signcolumn, 'auto')
    install_fake_lsp(
      signs: { 0 => 2 },
      ranges: { 0 => [{ first_col: 0, last_col: 5, severity: 2 }] },
    )
    _buf, win = make_buffer(['hello world'])
    out = @screen.send(:render_window, win)
    # Sign glyph color: warning = 214 / 'W '
    assert_match(/\e\[38;5;214mW /, out)
    # Inline underline open + close around 'hello'
    assert_match(/\e\[4;38;5;214m/, out)
    assert_match(/\e\[24;39m/, out)
  end

  def test_render_window_no_sign_column_when_no_diagnostics_and_auto
    @editor.settings.set(:lsp_enabled, true)
    @editor.settings.set(:signcolumn, 'auto')
    install_fake_lsp(signs: {}, ranges: {})
    _buf, win = make_buffer(['hello'])
    out = @screen.send(:render_window, win)
    refute_match(/\e\[4;38;5;\d+m/, out)
  end
end
