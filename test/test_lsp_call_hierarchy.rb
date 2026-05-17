# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# Two-step protocol: textDocument/prepareCallHierarchy returns
# CallHierarchyItem[]; the first item is used as input to
# callHierarchy/incomingCalls or callHierarchy/outgoingCalls.

class TestLspCallHierarchyClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_prepare_call_hierarchy_clears_and_sends_position
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_call_hierarchy_prepare_result = [{}]
    client.prepare_call_hierarchy('file:///x.rb', 2, 4)
    assert_nil client.last_call_hierarchy_prepare_result
    assert_equal 'textDocument/prepareCallHierarchy', sent[:method]
    assert_equal({ line: 2, character: 4 }, sent[:params][:position])
  end

  def test_incoming_and_outgoing_send_item_param
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    item = { name: 'foo', kind: 6, uri: 'file:///x.rb',
             range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
             selectionRange: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } } }

    client.call_hierarchy_incoming(item)
    assert_equal 'callHierarchy/incomingCalls', sent[:method]
    assert_equal item, sent[:params][:item]

    client.call_hierarchy_outgoing(item)
    assert_equal 'callHierarchy/outgoingCalls', sent[:method]
    assert_equal item, sent[:params][:item]
  end

  def test_handle_response_routes_to_correct_slot
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/prepareCallHierarchy', 'file:///x']
    client.instance_variable_get(:@pending)[2] = ['callHierarchy/incomingCalls', nil]
    client.instance_variable_get(:@pending)[3] = ['callHierarchy/outgoingCalls', nil]
    client.send(:handle_response, { id: 1, result: [{ name: 'foo' }] })
    client.send(:handle_response, { id: 2, result: [{ from: { name: 'bar' } }] })
    client.send(:handle_response, { id: 3, result: [{ to: { name: 'baz' } }] })
    assert_equal 'foo', client.last_call_hierarchy_prepare_result.first[:name]
    assert_equal 'bar', client.last_call_hierarchy_incoming_result.first.dig(:from, :name)
    assert_equal 'baz', client.last_call_hierarchy_outgoing_result.first.dig(:to, :name)
  end
end

class TestLspCallHierarchyManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :capabilities,
                  :last_call_hierarchy_prepare_result,
                  :last_call_hierarchy_incoming_result,
                  :last_call_hierarchy_outgoing_result,
                  :prepare_calls, :incoming_calls, :outgoing_calls

    def initialize
      @status = :running
      @capabilities = { callHierarchyProvider: true }
      @prepare_calls = []
      @incoming_calls = []
      @outgoing_calls = []
    end

    def prepare_call_hierarchy(uri, line, char)
      @prepare_calls << { uri: uri, line: line, char: char }
    end

    def call_hierarchy_incoming(item); @incoming_calls << item; end
    def call_hierarchy_outgoing(item); @outgoing_calls << item; end

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
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['x'] }
  end

  def test_request_prepare_call_hierarchy_uses_cursor
    @editor.instance_variable_set(:@line_index, 3)
    @editor.instance_variable_set(:@byte_pointer, 5)
    assert @manager.request_prepare_call_hierarchy(make_buffer)
    assert_equal({ uri: 'file:///x.rb', line: 3, char: 5 }, @client.prepare_calls.first)
  end

  def test_request_prepare_returns_unsupported_without_capability
    @client.capabilities = {}
    assert_equal :unsupported, @manager.request_prepare_call_hierarchy(make_buffer)
    assert_empty @client.prepare_calls
  end

  def test_incoming_and_outgoing_forward_item_to_client
    item = { name: 'foo' }
    assert @manager.request_call_hierarchy_incoming(make_buffer, item)
    assert @manager.request_call_hierarchy_outgoing(make_buffer, item)
    assert_equal [item], @client.incoming_calls
    assert_equal [item], @client.outgoing_calls
  end
end

class TestEditorLspCallHierarchy < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :prep_returns, :prepare_result,
                  :incoming_result, :outgoing_result,
                  :incoming_called_with, :outgoing_called_with

    def initialize
      @prep_returns = true
      @prepare_result = nil
      @incoming_result = nil
      @outgoing_result = nil
    end

    def flush_changes(_buf); false; end
    def request_prepare_call_hierarchy(_buf); @prep_returns; end
    def last_call_hierarchy_prepare_result; @prepare_result; end

    def request_call_hierarchy_incoming(_buf, item)
      @incoming_called_with = item
      true
    end
    def last_call_hierarchy_incoming_result; @incoming_result; end

    def request_call_hierarchy_outgoing(_buf, item)
      @outgoing_called_with = item
      true
    end
    def last_call_hierarchy_outgoing_result; @outgoing_result; end

    def pending_for?(_); false; end
    def pump; end
    def diagnostic_signs(_); {}; end
    def diagnostic_ranges(_); {}; end
    def diagnostics_for(_); []; end
    def document_highlights_by_line(_); {}; end
    def inlay_hints_by_line(_); {}; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = ['def caller_method', '  callee_method', 'end']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@filepath, '/tmp/x.rb')
  end

  def test_incoming_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_show_incoming_calls
  end

  def test_surfaces_unsupported_status_when_prepare_returns_unsupported
    @lsp.prep_returns = :unsupported
    assert @editor.lsp_show_incoming_calls
    assert_match(/does not support callHierarchy/, @editor.status_message.to_s)
  end

  def test_no_callable_symbol_status_when_prepare_returns_empty
    @lsp.prepare_result = []
    assert @editor.lsp_show_incoming_calls
    assert_match(/no callable symbol/, @editor.status_message.to_s)
  end

  def test_incoming_populates_quickfix_one_entry_per_fromRange
    @lsp.prepare_result = [{ name: 'callee', uri: 'file:///tmp/x.rb',
                              range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
                              selectionRange: { start: { line: 0, character: 4 }, end: { line: 0, character: 10 } } }]
    @lsp.incoming_result = [
      { from: { name: 'caller_a', uri: 'file:///tmp/a.rb',
                range: { start: { line: 5, character: 0 }, end: { line: 5, character: 1 } },
                selectionRange: { start: { line: 5, character: 4 }, end: { line: 5, character: 12 } } },
        fromRanges: [
          { start: { line: 6, character: 2 }, end: { line: 6, character: 13 } },
          { start: { line: 7, character: 2 }, end: { line: 7, character: 13 } },
        ] },
    ]
    assert @editor.lsp_show_incoming_calls
    entries = @editor.quickfix.entries
    assert_equal 2, entries.size, 'one quickfix entry per fromRange'
    assert_equal '/tmp/a.rb', entries[0].file
    assert_equal 7, entries[0].line  # 6 + 1 (1-based)
    assert_equal 3, entries[0].col   # 2 + 1
    assert_equal 'caller_a', entries[0].text
  end

  def test_outgoing_uses_to_field_and_fromRanges
    @lsp.prepare_result = [{ name: 'caller_method', uri: 'file:///tmp/x.rb',
                              range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
                              selectionRange: { start: { line: 0, character: 4 }, end: { line: 0, character: 17 } } }]
    @lsp.outgoing_result = [
      { to: { name: 'callee_method', uri: 'file:///tmp/x.rb',
              range: { start: { line: 4, character: 0 }, end: { line: 4, character: 1 } },
              selectionRange: { start: { line: 4, character: 4 }, end: { line: 4, character: 17 } } },
        fromRanges: [{ start: { line: 1, character: 2 }, end: { line: 1, character: 15 } }] },
    ]
    assert @editor.lsp_show_outgoing_calls
    entries = @editor.quickfix.entries
    assert_equal 1, entries.size
    assert_equal 'callee_method', entries[0].text
    assert_equal 2, entries[0].line
  end

  def test_falls_back_to_selection_range_when_fromRanges_empty
    @lsp.prepare_result = [{ name: 'x', uri: 'file:///tmp/x.rb',
                              range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
                              selectionRange: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } } }]
    @lsp.incoming_result = [
      { from: { name: 'caller', uri: 'file:///tmp/a.rb',
                range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
                selectionRange: { start: { line: 9, character: 4 }, end: { line: 9, character: 10 } } },
        fromRanges: [] },
    ]
    @editor.lsp_show_incoming_calls
    entries = @editor.quickfix.entries
    assert_equal 1, entries.size
    assert_equal 10, entries[0].line # selectionRange line 9 + 1
  end

  def test_no_results_status_message_when_calls_empty
    @lsp.prepare_result = [{ name: 'x', uri: 'file:///tmp/x.rb',
                              range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
                              selectionRange: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } } }]
    @lsp.incoming_result = []
    @lsp.outgoing_result = []
    @editor.lsp_show_incoming_calls
    assert_match(/no incoming calls/, @editor.status_message.to_s)
    @editor.lsp_show_outgoing_calls
    assert_match(/no outgoing calls/, @editor.status_message.to_s)
  end
end
