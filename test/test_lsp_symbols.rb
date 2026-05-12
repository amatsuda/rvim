# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

class TestLspSymbolsClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_handle_response_stores_documentSymbol_result
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/documentSymbol', 'file:///x']
    msg = { id: 1, result: [{ name: 'Foo', kind: 5,
                              range: { start: { line: 0, character: 0 }, end: { line: 5, character: 3 } },
                              selectionRange: { start: { line: 0, character: 6 }, end: { line: 0, character: 9 } } }] }
    client.send(:handle_response, msg)
    assert_equal 1, client.last_document_symbols_result.size
    assert_equal 'Foo', client.last_document_symbols_result.first[:name]
  end

  def test_document_symbol_clears_previous_result
    client = make_client
    client.define_singleton_method(:send_message) { |_| nil }
    client.last_document_symbols_result = [{}]
    client.document_symbol('file:///x')
    assert_nil client.last_document_symbols_result
  end
end

class TestLspSymbolsManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_document_symbols_result, :calls

    def initialize
      @status = :running
      @calls = []
      @last_document_symbols_result = nil
    end

    def document_symbol(uri)
      @calls << uri
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
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['x'] }
  end

  def test_request_document_symbols_calls_client
    assert @manager.request_document_symbols(make_buffer)
    assert_equal ['file:///x.rb'], @client.calls
  end

  def test_request_document_symbols_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_document_symbols(make_buffer)
  end
end

class TestEditorLspShowDocumentSymbols < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result

    def initialize
      @request_returns = true
      @result = nil
    end

    def request_document_symbols(_buf)
      @request_returns
    end

    def last_document_symbols_result
      @result
    end

    def did_open(_buf); end
    def did_close(_buf); end
    def note_change(_buf); false; end
    def maybe_pull_diagnostics(_buf); false; end
    def pump; end
    def diagnostic_signs(_); {}; end
    def diagnostic_ranges(_); {}; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = ['def foo', '  bar', 'end']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@filepath, '/tmp/x.rb')
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_show_document_symbols
  end

  def test_no_symbols_status_message
    @lsp.result = []
    assert @editor.lsp_show_document_symbols
    assert_match(/no symbols/, @editor.status_message.to_s)
    assert @editor.quickfix.empty?
  end

  def test_flattens_hierarchical_documentsymbols
    # class Foo containing method bar containing inner def baz
    @lsp.result = [{
      name: 'Foo', kind: 5,
      range: { start: { line: 0, character: 0 }, end: { line: 5, character: 3 } },
      selectionRange: { start: { line: 0, character: 6 }, end: { line: 0, character: 9 } },
      children: [{
        name: 'bar', kind: 6,
        range: { start: { line: 1, character: 2 }, end: { line: 4, character: 4 } },
        selectionRange: { start: { line: 1, character: 6 }, end: { line: 1, character: 9 } },
        children: [{
          name: 'baz', kind: 6,
          range: { start: { line: 2, character: 4 }, end: { line: 3, character: 4 } },
          selectionRange: { start: { line: 2, character: 8 }, end: { line: 2, character: 11 } },
        }],
      }],
    }]

    assert @editor.lsp_show_document_symbols
    entries = @editor.quickfix.entries
    assert_equal 3, entries.size
    assert_equal 'class Foo', entries[0].text
    assert_equal '  method bar', entries[1].text
    assert_equal '    method baz', entries[2].text
    assert_equal 1, entries[0].line   # 1-based
    assert_equal 7, entries[0].col    # selectionRange char 6 + 1
  end

  def test_handles_flat_symbolinformation
    # Pre-3.10 servers return SymbolInformation[] (no children, has location)
    @lsp.result = [
      { name: 'Foo', kind: 5,
        location: { uri: 'file:///tmp/x.rb',
                    range: { start: { line: 0, character: 0 }, end: { line: 5, character: 3 } } } },
      { name: 'bar', kind: 6, containerName: 'Foo',
        location: { uri: 'file:///tmp/x.rb',
                    range: { start: { line: 1, character: 2 }, end: { line: 4, character: 4 } } } },
    ]
    assert @editor.lsp_show_document_symbols
    entries = @editor.quickfix.entries
    assert_equal 2, entries.size
    assert_equal 'class Foo', entries[0].text
    assert_equal 'method bar', entries[1].text
    assert_equal '/tmp/x.rb', entries[0].file
  end

  def test_unknown_symbol_kind_falls_back_to_symbol
    @lsp.result = [{
      name: 'Mystery', kind: 999,
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
      selectionRange: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
    }]
    assert @editor.lsp_show_document_symbols
    assert_equal 'symbol Mystery', @editor.quickfix.entries.first.text
  end

  def test_show_list_is_invoked
    @lsp.result = [{
      name: 'Foo', kind: 5,
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } },
      selectionRange: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } },
    }]
    assert @editor.lsp_show_document_symbols
    refute_nil @editor.list_view, 'expected listing overlay to be populated'
  end
end
