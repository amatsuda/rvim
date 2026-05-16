# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# textDocument/documentHighlight covers three layers:
#   - Client request shape + handle_response stashing
#   - Manager wiring: request, cache, debounce, by-line bucket
#   - Screen overlay: byte-range conversion, SGR-aware splice, ordering

class TestLspDocumentHighlightClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_document_highlight_clears_previous_and_sends_position
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_document_highlights_result = [{}]
    client.document_highlight('file:///x.rb', 1, 4)
    assert_nil client.last_document_highlights_result
    assert_equal 'textDocument/documentHighlight', sent[:method]
    assert_equal({ line: 1, character: 4 }, sent[:params][:position])
  end

  def test_handle_response_stashes_highlights_array
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/documentHighlight', 'file:///x']
    msg = { id: 1, result: [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } }, kind: 2 },
    ] }
    client.send(:handle_response, msg)
    assert_equal 1, client.last_document_highlights_result.size
  end
end

class TestLspDocumentHighlightManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_document_highlights_result, :calls

    def initialize
      @status = :running
      @calls = []
      @last_document_highlights_result = nil
    end

    def document_highlight(uri, line, char)
      @calls << { uri: uri, line: line, char: char }
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

  def make_buffer
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['x = 1'] }
  end

  def test_request_document_highlight_uses_cursor_position
    @editor.instance_variable_set(:@line_index, 2)
    @editor.instance_variable_set(:@byte_pointer, 5)
    assert @manager.request_document_highlight(make_buffer)
    assert_equal({ uri: 'file:///x.rb', line: 2, char: 5 }, @client.calls.first)
  end

  def test_maybe_pull_skips_when_cursor_unchanged_and_debounce_active
    buf = make_buffer
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    assert @manager.maybe_pull_document_highlight(buf)
    refute @manager.maybe_pull_document_highlight(buf), 'second pull at same cursor should be skipped'
    assert_equal 1, @client.calls.size
  end

  def test_maybe_pull_runs_when_cursor_moved
    buf = make_buffer
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    assert @manager.maybe_pull_document_highlight(buf)
    @editor.instance_variable_set(:@byte_pointer, 5)
    assert @manager.maybe_pull_document_highlight(buf)
    assert_equal 2, @client.calls.size
  end

  def test_request_drains_pending_result_before_clearing_for_next_request
    # Regression: a response that arrived between renders must land in
    # the cache. The client wipes `last_document_highlights_result`
    # the moment we send the next request, so `request_document_highlight`
    # has to drain first or the highlights would never be visible.
    buf = make_buffer
    @client.last_document_highlights_result = [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } } },
    ]
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 5)
    assert @manager.request_document_highlight(buf)
    assert_nil @client.last_document_highlights_result, 'should have been drained before new send'

    # The next by_line read sees the drained cache, NOT an empty hash.
    out = @manager.document_highlights_by_line(buf)
    assert_equal 1, out[0].size
  end

  def test_cursor_move_invalidates_previous_cache_immediately
    buf = make_buffer
    @client.last_document_highlights_result = [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } } }]
    @manager.document_highlights_by_line(buf) # cache the result for cursor [nil,nil]

    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    assert @manager.maybe_pull_document_highlight(buf) # records cursor [0,0]

    @editor.instance_variable_set(:@byte_pointer, 10) # moved
    @manager.maybe_pull_document_highlight(buf)
    # Cache should have been cleared so we don't render stale highlights.
    assert_equal({}, @manager.document_highlights_by_line(buf).reject { |_, v| v.empty? })
  end

  def test_by_line_buckets_and_sorts
    buf = make_buffer
    @client.last_document_highlights_result = [
      { range: { start: { line: 1, character: 8 }, end: { line: 1, character: 10 } } },
      { range: { start: { line: 0, character: 5 }, end: { line: 0, character: 7 } } },
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 2 } } },
    ]
    out = @manager.document_highlights_by_line(buf)
    assert_equal [0, 5], out[0].map { |h| h.dig(:range, :start, :character) }
    assert_equal [8], out[1].map { |h| h.dig(:range, :start, :character) }
  end
end

class TestScreenDocumentHighlightOverlay < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_overlay_returns_input_when_highlights_empty
    out = @screen.send(:apply_document_highlight_overlay, 'foo bar', [], 'foo bar')
    assert_equal 'foo bar', out
  end

  def test_overlay_wraps_each_occurrence_with_bg_sgr
    highlights = [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } }, kind: 2 },
      { range: { start: { line: 0, character: 8 }, end: { line: 0, character: 11 } }, kind: 2 },
    ]
    out = @screen.send(:apply_document_highlight_overlay, 'foo bar foo', highlights, 'foo bar foo')
    assert_match(/\e\[48;5;240mfoo\e\[49m bar \e\[48;5;240mfoo\e\[49m/, out)
  end

  def test_overlay_skips_multi_line_ranges
    highlights = [
      { range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } } },
    ]
    out = @screen.send(:apply_document_highlight_overlay, 'foo', highlights, 'foo')
    refute_match(/\e\[48;5;240m/, out)
  end

  def test_overlay_works_around_existing_sgr_codes
    pre = "\e[31mfoo\e[39m bar"
    highlights = [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } } }]
    out = @screen.send(:apply_document_highlight_overlay, pre, highlights, 'foo bar')
    # The bg SGR wraps the colored foo; the original fg color is
    # preserved, the bg open/close brackets the text content. The
    # exact relative ordering of the two opens doesn't matter to the
    # terminal — both SGRs are simultaneously active over "foo".
    assert_match(/\e\[48;5;240m.*foo.*\e\[49m bar/, out)
    assert_match(/\e\[31m/, out)
    assert_match(/\e\[39m/, out)
  end

  def test_char_to_byte_for_ascii_is_identity
    assert_equal 0, @screen.send(:char_to_byte, 'hello', 0)
    assert_equal 3, @screen.send(:char_to_byte, 'hello', 3)
    assert_equal 5, @screen.send(:char_to_byte, 'hello', 5)
  end

  def test_char_to_byte_for_multibyte
    # 'aあ' = a(1B) + あ(3B). char idx 1 = 1 byte; char idx 2 = 4 bytes.
    assert_equal 1, @screen.send(:char_to_byte, 'aあ', 1)
    assert_equal 4, @screen.send(:char_to_byte, 'aあ', 2)
  end
end
