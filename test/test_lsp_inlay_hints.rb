# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# Inlay hints (textDocument/inlayHint) cover three layers:
#   - Client request shape + handle_response stashing
#   - Manager wiring: request_inlay_hints, by-line bucketing,
#     throttled auto-pull
#   - Screen overlay: dim-styled splice at character positions,
#     paddingLeft/paddingRight, cursor-line skip, SGR-skipping walk

class TestLspInlayHintsClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_inlay_hint_clears_previous_result_and_sends_range
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_inlay_hints_result = [{ label: 'old' }]
    range = { start: { line: 0, character: 0 }, end: { line: 10, character: 0 } }
    client.inlay_hint('file:///x.rb', range)
    assert_nil client.last_inlay_hints_result
    assert_equal 'textDocument/inlayHint', sent[:method]
    assert_equal({ uri: 'file:///x.rb' }, sent[:params][:textDocument])
    assert_equal range, sent[:params][:range]
  end

  def test_handle_response_stores_inlay_hints_array
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/inlayHint', 'file:///x']
    msg = { id: 1, result: [{ position: { line: 0, character: 5 }, label: ': Integer' }] }
    client.send(:handle_response, msg)
    assert_equal 1, client.last_inlay_hints_result.size
    assert_equal ': Integer', client.last_inlay_hints_result.first[:label]
  end

  def test_handle_response_stores_null_result_as_nil
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/inlayHint', 'file:///x']
    client.send(:handle_response, id: 1, result: nil)
    assert_nil client.last_inlay_hints_result
  end
end

class TestLspInlayHintsManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_inlay_hints_result, :inlay_hint_calls

    def initialize
      @status = :running
      @inlay_hint_calls = []
      @last_inlay_hints_result = nil
    end

    def inlay_hint(uri, range)
      @inlay_hint_calls << { uri: uri, range: range }
    end

    def diagnostics; {}; end
    def pending_for?(_); false; end
    def pump; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @manager = Rvim::Lsp::Manager.new(@editor)
    @manager.define_singleton_method(:filetype_for) { |_| :ruby }
    @manager.define_singleton_method(:buffer_uri) { |_| 'file:///x.rb' }
    @client = FakeClient.new
    @manager.instance_variable_set(:@clients, { ruby: @client })
  end

  def make_buffer(lines = ['x = 1'])
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = lines }
  end

  def test_request_inlay_hints_sends_whole_buffer_range
    buf = make_buffer(%w[a b c])
    assert @manager.request_inlay_hints(buf)
    call = @client.inlay_hint_calls.first
    assert_equal 'file:///x.rb', call[:uri]
    assert_equal({ line: 0, character: 0 }, call[:range][:start])
    assert_equal({ line: 3, character: 0 }, call[:range][:end])
  end

  def test_request_inlay_hints_returns_false_without_running_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_inlay_hints(make_buffer)
  end

  def test_maybe_pull_inlay_hints_throttles_within_interval
    buf = make_buffer
    assert @manager.maybe_pull_inlay_hints(buf)
    # Second call within HINTS_PULL_INTERVAL must be a no-op.
    refute @manager.maybe_pull_inlay_hints(buf)
    assert_equal 1, @client.inlay_hint_calls.size
  end

  def test_maybe_pull_inlay_hints_returns_false_for_nil_buffer
    refute @manager.maybe_pull_inlay_hints(nil)
  end

  def test_inlay_hints_by_line_buckets_by_line_and_sorts_by_character
    buf = make_buffer
    @client.last_inlay_hints_result = [
      { position: { line: 1, character: 10 }, label: 'b' },
      { position: { line: 0, character: 5 },  label: 'a1' },
      { position: { line: 0, character: 1 },  label: 'a0' },
    ]
    out = @manager.inlay_hints_by_line(buf)
    assert_equal %w[a0 a1], out[0].map { |h| h[:label] }
    assert_equal %w[b], out[1].map { |h| h[:label] }
  end

  def test_inlay_hints_by_line_caches_so_repeat_calls_keep_returning_results
    buf = make_buffer
    @client.last_inlay_hints_result = [{ position: { line: 0, character: 0 }, label: 'x' }]
    first = @manager.inlay_hints_by_line(buf)
    # Result was drained off the client; second call must still return cache.
    assert_nil @client.last_inlay_hints_result
    second = @manager.inlay_hints_by_line(buf)
    assert_equal first[0].first[:label], second[0].first[:label]
  end

  def test_inlay_hints_by_line_ignores_hints_missing_position
    buf = make_buffer
    @client.last_inlay_hints_result = [{ label: 'no-pos' }]
    out = @manager.inlay_hints_by_line(buf)
    assert_equal({}, out.reject { |_, v| v.empty? })
  end
end

class TestLspInlayHintsScreenOverlay < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_overlay_returns_input_when_hints_empty
    out = @screen.send(:apply_inlay_hints_overlay, 'hello', [])
    assert_equal 'hello', out
  end

  def test_overlay_splices_label_at_character_position
    hints = [{ position: { line: 0, character: 5 }, label: ': Integer' }]
    out = @screen.send(:apply_inlay_hints_overlay, 'hello world', hints)
    # Label appears between 'hello' and ' world', wrapped in dim SGR.
    assert_match(/hello\e\[3;38;5;240m: Integer\e\[23;39m world/, out)
  end

  def test_overlay_emits_padding_left_and_right
    hints = [{
      position: { line: 0, character: 1 },
      label: ':Int',
      paddingLeft: true, paddingRight: true,
    }]
    out = @screen.send(:apply_inlay_hints_overlay, 'ab', hints)
    assert_match(/a\e\[3;38;5;240m :Int \e\[23;39mb/, out)
  end

  def test_overlay_handles_label_part_array
    hints = [{
      position: { line: 0, character: 0 },
      label: [{ value: 'foo' }, { value: '=' }, { value: 'bar' }],
    }]
    out = @screen.send(:apply_inlay_hints_overlay, 'x', hints)
    assert_match(/\e\[3;38;5;240mfoo=bar\e\[23;39m/, out)
  end

  def test_overlay_emits_trailing_hint_past_end_of_line
    hints = [{ position: { line: 0, character: 5 }, label: 'trail' }]
    out = @screen.send(:apply_inlay_hints_overlay, 'abc', hints)
    # The hint anchored at col 5 is past 'abc' (3 chars); should still emit.
    assert_match(/abc\e\[3;38;5;240mtrail\e\[23;39m/, out)
  end

  def test_overlay_skips_existing_sgr_when_counting_chars
    # 'x = 1' with 'x' pre-wrapped in syntax color. Inlay hint at char
    # position 1 (right after 'x') must land *after* the closing SGR
    # of the syntax color, not inside it.
    pre = "\e[31mx\e[39m = 1"
    hints = [{ position: { line: 0, character: 1 }, label: ':Int' }]
    out = @screen.send(:apply_inlay_hints_overlay, pre, hints)
    assert_match(/\e\[31mx\e\[39m\e\[3;38;5;240m:Int\e\[23;39m = 1/, out)
  end

  def test_overlay_uses_italic_and_muted_gray_sgr_styling
    hints = [{ position: { line: 0, character: 0 }, label: 'h' }]
    out = @screen.send(:apply_inlay_hints_overlay, 'x', hints)
    assert_match(/\e\[3;38;5;240mh\e\[23;39m/, out)
  end

  def test_render_window_skips_inlay_hints_on_cursor_line
    @editor.settings.set(:lsp_enabled, true)
    fake = Class.new do
      def diagnostic_signs(_); {}; end
      def diagnostic_ranges(_); {}; end
      def diagnostics_for(_); []; end
      def inlay_hints_by_line(_)
        { 0 => [{ position: { line: 0, character: 1 }, label: ':GHOST' }] }
      end
      def pump; end
    end.new
    @editor.instance_variable_set(:@lsp, fake)

    buf = Rvim::Buffer.new(1, nil)
    buf.lines = ['ab']
    @editor.instance_variable_set(:@buffer_of_lines, buf.lines)
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf)
    win.row = 0; win.col = 0; win.width = 40; win.height = 3
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)
    @editor.instance_variable_set(:@line_index, 0)

    out = @screen.send(:render_window, win)
    refute_match(/:GHOST/, out, 'inlay hint should be suppressed on the cursor line')
  end

  def test_render_window_renders_inlay_hint_on_non_cursor_line
    @editor.settings.set(:lsp_enabled, true)
    fake = Class.new do
      def diagnostic_signs(_); {}; end
      def diagnostic_ranges(_); {}; end
      def diagnostics_for(_); []; end
      def inlay_hints_by_line(_)
        { 1 => [{ position: { line: 1, character: 0 }, label: ':T' }] }
      end
      def pump; end
    end.new
    @editor.instance_variable_set(:@lsp, fake)

    buf = Rvim::Buffer.new(1, nil)
    buf.lines = ['cursor here', 'other line']
    @editor.instance_variable_set(:@buffer_of_lines, buf.lines)
    @editor.instance_variable_set(:@current_buffer, buf)
    win = Rvim::Window.new(buf)
    win.row = 0; win.col = 0; win.width = 40; win.height = 4
    @editor.instance_variable_set(:@windows, [win])
    @editor.instance_variable_set(:@current_window, win)
    @editor.instance_variable_set(:@line_index, 0)

    out = @screen.send(:render_window, win)
    assert_match(/\e\[3;38;5;240m:T\e\[23;39m/, out)
  end
end
