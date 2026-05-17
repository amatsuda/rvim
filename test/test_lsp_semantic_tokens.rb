# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# textDocument/semanticTokens/full covers three layers:
#   - Client request shape + handle_response stashing
#   - Manager decoder for the delta-encoded 5-int sequence
#   - Screen overlay paints fg-color SGR per token using a type palette

class TestLspSemanticTokensClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_semantic_tokens_full_clears_previous_and_sends_uri
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_semantic_tokens_result = { data: [1] }
    client.semantic_tokens_full('file:///x.rb')
    assert_nil client.last_semantic_tokens_result
    assert_equal 'textDocument/semanticTokens/full', sent[:method]
    assert_equal({ uri: 'file:///x.rb' }, sent[:params][:textDocument])
  end

  def test_handle_response_stashes_result_object
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/semanticTokens/full', 'file:///x']
    msg = { id: 1, result: { resultId: '1', data: [0, 6, 7, 2, 1] } }
    client.send(:handle_response, msg)
    assert_equal '1', client.last_semantic_tokens_result[:resultId]
    assert_equal [0, 6, 7, 2, 1], client.last_semantic_tokens_result[:data]
  end
end

class TestLspSemanticTokensManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :capabilities, :last_semantic_tokens_result, :calls

    def initialize
      @status = :running
      @capabilities = {
        semanticTokensProvider: {
          legend: {
            tokenTypes: %w[namespace type class enum interface struct typeParameter parameter variable property enumMember event function method macro keyword modifier comment string number regexp operator decorator],
            tokenModifiers: %w[declaration definition readonly static deprecated abstract async modification documentation defaultLibrary],
          },
          full: { delta: true },
          range: true,
        },
      }
      @calls = []
    end

    def semantic_tokens_full(uri); @calls << uri; end
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
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['class Greeter'] }
  end

  # ----- request_semantic_tokens -----

  def test_request_calls_client
    assert @manager.request_semantic_tokens(make_buffer)
    assert_equal ['file:///x.rb'], @client.calls
  end

  def test_request_unsupported_without_provider
    @client.capabilities = {}
    assert_equal :unsupported, @manager.request_semantic_tokens(make_buffer)
  end

  def test_request_unsupported_when_provider_lacks_full
    @client.capabilities = { semanticTokensProvider: { range: true } }
    assert_equal :unsupported, @manager.request_semantic_tokens(make_buffer)
  end

  def test_request_supported_when_full_is_true
    @client.capabilities = { semanticTokensProvider: { full: true } }
    assert @manager.request_semantic_tokens(make_buffer)
  end

  # ----- maybe_pull_semantic_tokens -----

  # Pretend note_change synced this buffer's current fingerprint long
  # enough ago that the settle window has elapsed.
  private def sync_buffer(buf)
    fp = buf.lines.hash
    @manager.instance_variable_get(:@synced_fingerprints)[buf.id] = fp
    @manager.instance_variable_get(:@synced_at)[buf.id] = -1.0
  end

  def test_maybe_pull_skips_when_fingerprint_unchanged
    buf = make_buffer
    sync_buffer(buf)
    assert @manager.maybe_pull_semantic_tokens(buf)
    refute @manager.maybe_pull_semantic_tokens(buf), 'second pull on same buffer skipped'
    assert_equal 1, @client.calls.size
  end

  def test_maybe_pull_re_pulls_on_buffer_change
    buf = make_buffer
    sync_buffer(buf)
    assert @manager.maybe_pull_semantic_tokens(buf)
    buf.lines = ['class Greeter', '  def hello; end']
    sync_buffer(buf)
    assert @manager.maybe_pull_semantic_tokens(buf)
    assert_equal 2, @client.calls.size
  end

  def test_maybe_pull_waits_for_did_change_to_sync_first
    # Race fix: don't ask the server for tokens at a fingerprint the
    # server hasn't seen yet.
    buf = make_buffer
    # No sync at all — synced_fingerprints empty.
    refute @manager.maybe_pull_semantic_tokens(buf)
    assert_empty @client.calls
  end

  def test_maybe_pull_waits_for_settle_after_did_change
    # Race fix: ruby-lsp processes didChange on a worker thread; we
    # wait a tick before requesting so the worker has time to apply
    # the edit and refresh its parse tree.
    buf = make_buffer
    @manager.instance_variable_get(:@synced_fingerprints)[buf.id] = buf.lines.hash
    @manager.instance_variable_get(:@synced_at)[buf.id] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    refute @manager.maybe_pull_semantic_tokens(buf)
    assert_empty @client.calls
  end

  # ----- decode_semantic_tokens -----

  def test_decode_single_token
    legend = %w[namespace type class enum interface struct typeParameter parameter]
    out = @manager.decode_semantic_tokens([0, 6, 7, 2, 0], legend, %w[declaration])
    assert_equal 1, out[0].size
    tok = out[0].first
    assert_equal 6, tok[:start]
    assert_equal 7, tok[:length]
    assert_equal 'class', tok[:type]
    assert_equal [], tok[:modifiers]
  end

  def test_decode_multiple_tokens_same_line_uses_relative_start
    legend = %w[namespace type class enum interface struct typeParameter parameter]
    # Two tokens on line 0: at chars 6-13, then 20-27.
    # Second token's deltaStart is 14 (20 - 6).
    out = @manager.decode_semantic_tokens([0, 6, 7, 2, 0, 0, 14, 7, 7, 0], legend, %w[declaration])
    assert_equal 2, out[0].size
    assert_equal 6, out[0][0][:start]
    assert_equal 20, out[0][1][:start]
    assert_equal 'parameter', out[0][1][:type]
  end

  def test_decode_resets_start_on_new_line
    legend = %w[namespace type class enum interface struct typeParameter parameter]
    # Token on line 0 then on line 2 at char 4. dl=2, ds=4 (absolute).
    out = @manager.decode_semantic_tokens([0, 6, 7, 2, 0, 2, 4, 4, 7, 0], legend, %w[declaration])
    assert_equal [6], out[0].map { |t| t[:start] }
    assert_equal [4], out[2].map { |t| t[:start] }
  end

  def test_decode_unpacks_modifier_bits
    out = @manager.decode_semantic_tokens([0, 0, 1, 0, 0b101], %w[x], %w[a b c])
    assert_equal %w[a c], out[0][0][:modifiers]
  end

  def test_decode_unknown_type_index_falls_back_to_unknown
    out = @manager.decode_semantic_tokens([0, 0, 1, 99, 0], %w[a b], %w[m])
    assert_equal 'unknown', out[0][0][:type]
  end

  def test_decode_empty_data_returns_empty_hash
    out = @manager.decode_semantic_tokens([], %w[a], %w[m])
    assert_equal({}, out.reject { |_, v| v.empty? })
  end

  # ----- semantic_tokens_by_line drains client result into cache -----

  def test_by_line_drains_result_into_cache_and_decodes
    buf = make_buffer
    @client.last_semantic_tokens_result = { data: [0, 6, 7, 2, 0] }
    out = @manager.semantic_tokens_by_line(buf)
    assert_equal 1, out[0].size
    assert_equal 'class', out[0][0][:type]
    assert_nil @client.last_semantic_tokens_result, 'drained'
    # Subsequent calls return the cached value.
    assert_equal 1, @manager.semantic_tokens_by_line(buf)[0].size
  end
end

class TestScreenSemanticTokensOverlay < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_overlay_returns_input_when_tokens_empty
    out = @screen.send(:apply_semantic_tokens_overlay, 'class Greeter', [], 'class Greeter')
    assert_equal 'class Greeter', out
  end

  def test_overlay_wraps_token_with_type_color
    tokens = [{ start: 6, length: 7, type: 'class', modifiers: [] }]
    out = @screen.send(:apply_semantic_tokens_overlay, 'class Greeter', tokens, 'class Greeter')
    # class -> SGR 178 (gold)
    assert_match(/\e\[38;5;178mGreeter\e\[39m/, out)
  end

  def test_overlay_skips_unknown_types
    tokens = [{ start: 0, length: 3, type: 'unknown', modifiers: [] }]
    out = @screen.send(:apply_semantic_tokens_overlay, 'foo', tokens, 'foo')
    refute_match(/\e\[38;5;/, out)
  end

  def test_overlay_handles_multiple_tokens_per_line
    tokens = [
      { start: 0, length: 5, type: 'keyword', modifiers: [] },
      { start: 6, length: 7, type: 'class', modifiers: [] },
    ]
    out = @screen.send(:apply_semantic_tokens_overlay, 'class Greeter', tokens, 'class Greeter')
    assert_match(/\e\[38;5;197mclass\e\[39m/, out)
    assert_match(/\e\[38;5;178mGreeter\e\[39m/, out)
  end

  def test_overlay_skips_existing_sgr_when_counting_chars
    pre = "\e[31mclass\e[39m Greeter"
    tokens = [{ start: 6, length: 7, type: 'class', modifiers: [] }]
    out = @screen.send(:apply_semantic_tokens_overlay, pre, tokens, 'class Greeter')
    # Greeter still gets wrapped; pre-existing SGR survives intact.
    assert_match(/\e\[38;5;178mGreeter\e\[39m/, out)
    assert_match(/\e\[31m/, out)
    assert_match(/\e\[39m/, out)
  end
end
