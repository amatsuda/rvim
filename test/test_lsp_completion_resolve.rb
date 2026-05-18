# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# completionItem/resolve fetches per-item details (signature,
# documentation) the server lazily computes. We resolve only the
# currently-selected candidate so we never need a batch round-trip.
# Layers tested:
#   - Client: request shape + handle_response stash
#   - Manager: capability gate on completionProvider.resolveProvider
#   - Editor: detail popup population, in-flight selection-changed
#     dropping of out-of-band responses

class TestLspCompletionResolveClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_resolve_clears_previous_and_sends_item_verbatim
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |b| sent = b }
    client.last_completion_item_resolve_result = { label: 'old' }
    item = { label: 'gsub', kind: 3, data: { method: 'gsub' } }
    client.completion_item_resolve(item)
    assert_nil client.last_completion_item_resolve_result
    assert_equal 'completionItem/resolve', sent[:method]
    # CompletionItem is sent as the JSON-RPC `params` directly.
    assert_equal item, sent[:params]
  end

  def test_handle_response_stashes_resolved_item
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['completionItem/resolve', nil]
    msg = { id: 1, result: { label: 'gsub', detail: 'gsub(pattern, replacement) -> String',
                              documentation: { kind: 'markdown', value: '**docs**' } } }
    client.send(:handle_response, msg)
    assert_equal 'gsub', client.last_completion_item_resolve_result[:label]
    assert_match(/docs/, client.last_completion_item_resolve_result.dig(:documentation, :value))
  end
end

class TestLspCompletionResolveManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :capabilities, :last_completion_item_resolve_result, :calls
    def initialize(caps)
      @status = :running
      @capabilities = caps
      @calls = []
    end
    def completion_item_resolve(item); @calls << item; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @manager = Rvim::Lsp::Manager.new(@editor)
    @manager.define_singleton_method(:filetype_for) { |_| :ruby }
    @manager.define_singleton_method(:buffer_uri) { |_| 'file:///x' }
  end

  def buf
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['x'] }
  end

  def test_returns_unsupported_without_resolveProvider
    @manager.instance_variable_set(:@clients,
      ruby: FakeClient.new(completionProvider: { resolveProvider: false }))
    assert_equal :unsupported, @manager.request_completion_item_resolve(buf, label: 'foo')
  end

  def test_forwards_item_to_client_when_supported
    client = FakeClient.new(completionProvider: { resolveProvider: true })
    @manager.instance_variable_set(:@clients, ruby: client)
    item = { label: 'foo' }
    assert @manager.request_completion_item_resolve(buf, item)
    assert_equal [item], client.calls
  end
end

class TestEditorCompletionDetail < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :resolve_result, :resolve_supported, :resolve_calls

    def initialize
      @resolve_supported = true
      @resolve_result = nil
      @resolve_calls = []
    end

    def request_completion_item_resolve(_buf, item)
      @resolve_calls << item
      @resolve_supported ? true : :unsupported
    end
    def last_completion_item_resolve_result; @resolve_result; end
    def clear_completion_item_resolve_result; @resolve_result = nil; end

    # Everything else completion-flow expects:
    def request_completion(_buf); true; end
    def last_completion_result; nil; end
    def flush_changes(_buf); false; end
    def completion_trigger_characters(_buf); []; end
    def diagnostic_signs(_); {}; end
    def diagnostic_ranges(_); {}; end
    def diagnostics_for(_); []; end
    def document_highlights_by_line(_); {}; end
    def inlay_hints_by_line(_); {}; end
    def semantic_tokens_by_line(_); {}; end
    def pending_for?(_); false; end
    def pump; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = ['foo.bar']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)

    # Pretend the completion popup is already up with two candidates,
    # each with a known CompletionItem object behind it.
    @editor.instance_variable_set(:@completion_active, true)
    @editor.instance_variable_set(:@completion_candidates, %w[bar baz])
    @editor.instance_variable_set(:@completion_index, 0)
    @editor.instance_variable_set(:@completion_items_by_label, {
      'bar' => { label: 'bar', data: 1 },
      'baz' => { label: 'baz', data: 2 },
    })
  end

  # ----- kick_off_completion_detail -----

  def test_renders_inline_documentation_immediately
    @editor.instance_variable_get(:@completion_items_by_label)['bar'][:detail] = 'String#bar'
    @editor.instance_variable_get(:@completion_items_by_label)['bar'][:documentation] = 'inline doc'
    @editor.send(:kick_off_completion_detail)
    popup = @editor.completion_detail_popup
    refute_nil popup
    assert(popup.contents.any? { |l| l =~ /String#bar/ })
    assert(popup.contents.any? { |l| l =~ /inline doc/ })
  end

  def test_clears_detail_when_no_lsp_item_behind_label
    @editor.instance_variable_get(:@completion_items_by_label).delete('bar')
    @editor.instance_variable_set(:@completion_detail_popup, :stale)
    @editor.send(:kick_off_completion_detail)
    assert_nil @editor.completion_detail_popup
  end

  def test_sends_resolve_when_item_lacks_doc
    @editor.send(:kick_off_completion_detail)
    assert_equal 1, @lsp.resolve_calls.size
    assert_equal 'bar', @lsp.resolve_calls.first[:label]
  end

  # ----- pump_completion_detail -----

  def test_pump_promotes_resolved_item_to_detail_popup
    @editor.send(:kick_off_completion_detail)
    @lsp.resolve_result = { label: 'bar', detail: 'String#bar',
                            documentation: { value: 'resolved doc' } }
    @editor.pump_completion_detail
    refute_nil @editor.completion_detail_popup
    assert(@editor.completion_detail_popup.contents.any? { |l| l =~ /resolved doc/ })
  end

  def test_pump_ignores_response_for_a_different_candidate
    # Started resolve for 'bar', then user moved to 'baz'. The
    # in-flight bar-response should be dropped on arrival.
    @editor.send(:kick_off_completion_detail) # pending = 'bar'
    @editor.instance_variable_set(:@completion_index, 1) # user moved to 'baz'
    @lsp.resolve_result = { label: 'bar', detail: 'String#bar' }
    @editor.pump_completion_detail
    # baz still has no docs in our map; popup stays nil.
    assert_nil @editor.completion_detail_popup
  end

  def test_cancel_completion_clears_detail_popup
    @editor.instance_variable_set(:@completion_detail_popup, :stale)
    @editor.send(:cancel_completion)
    assert_nil @editor.completion_detail_popup
    assert_empty @editor.instance_variable_get(:@completion_items_by_label)
  end
end
