# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# workspace/symbol covers three layers:
#   - Client request shape + handle_response stashing
#   - Manager wiring: request_workspace_symbols / last/clear accessors
#   - Editor lsp_show_workspace_symbols: polling, quickfix population,
#     reuse of the SymbolInformation flatten_symbols branch.

class TestLspWorkspaceSymbolsClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_workspace_symbol_clears_previous_and_sends_query
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_workspace_symbols_result = [{}]
    client.workspace_symbol('foo')
    assert_nil client.last_workspace_symbols_result
    assert_equal 'workspace/symbol', sent[:method]
    assert_equal 'foo', sent[:params][:query]
  end

  def test_workspace_symbol_coerces_query_to_string
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.workspace_symbol(nil)
    assert_equal '', sent[:params][:query]
  end

  def test_handle_response_stashes_workspace_symbols_result
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['workspace/symbol', nil]
    msg = { id: 1, result: [
      { name: 'Foo', kind: 5, location: {
        uri: 'file:///a.rb',
        range: { start: { line: 1, character: 6 }, end: { line: 1, character: 9 } },
      } },
    ] }
    client.send(:handle_response, msg)
    assert_equal 1, client.last_workspace_symbols_result.size
    assert_equal 'Foo', client.last_workspace_symbols_result.first[:name]
  end
end

class TestLspWorkspaceSymbolsManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_workspace_symbols_result, :calls

    def initialize
      @status = :running
      @calls = []
      @last_workspace_symbols_result = nil
    end

    def workspace_symbol(query)
      @calls << query
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

  def test_request_workspace_symbols_calls_client_with_query
    assert @manager.request_workspace_symbols(make_buffer, 'foo')
    assert_equal ['foo'], @client.calls
  end

  def test_request_workspace_symbols_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_workspace_symbols(make_buffer, 'foo')
  end

  def test_last_and_clear_workspace_symbols_result
    @client.last_workspace_symbols_result = [{ name: 'X' }]
    assert_equal 'X', @manager.last_workspace_symbols_result.first[:name]
    @manager.clear_workspace_symbols_result
    assert_nil @client.last_workspace_symbols_result
  end
end

class TestEditorLspShowWorkspaceSymbols < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result, :request_calls

    def initialize
      @request_returns = true
      @result = nil
      @request_calls = []
    end

    def request_workspace_symbols(_buf, query)
      @request_calls << query
      @request_returns
    end

    def last_workspace_symbols_result
      @result
    end

    def did_open(_buf); end
    def did_close(_buf); end
    def note_change(_buf); false; end
    def maybe_pull_diagnostics(_buf); false; end
    def maybe_pull_inlay_hints(_buf); false; end
    def flush_changes(_buf); false; end
    def pending_for?(_); false; end
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
    @buf.lines = ['def foo', 'end']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@filepath, '/tmp/x.rb')
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_show_workspace_symbols('foo')
  end

  def test_returns_false_when_request_fails
    @lsp.request_returns = false
    refute @editor.lsp_show_workspace_symbols('foo')
  end

  def test_passes_query_through_to_manager
    @lsp.result = []
    @editor.lsp_show_workspace_symbols('xyz')
    assert_equal ['xyz'], @lsp.request_calls
  end

  def test_no_matches_status_message_includes_query
    @lsp.result = []
    assert @editor.lsp_show_workspace_symbols('foo')
    assert_match(/no symbols match/, @editor.status_message.to_s)
    assert_match(/"foo"/, @editor.status_message.to_s)
    assert @editor.quickfix.empty?
  end

  def test_populates_quickfix_with_one_entry_per_result
    @lsp.result = [
      { name: 'FooBar', kind: 5, location: {
        uri: 'file:///tmp/a.rb',
        range: { start: { line: 0, character: 6 }, end: { line: 0, character: 12 } },
      } },
      { name: 'foozle', kind: 6, containerName: 'Helpers', location: {
        uri: 'file:///tmp/b.rb',
        range: { start: { line: 1, character: 6 }, end: { line: 1, character: 12 } },
      } },
    ]
    assert @editor.lsp_show_workspace_symbols('foo')
    entries = @editor.quickfix.entries
    assert_equal 2, entries.size
    assert_equal 'class FooBar', entries[0].text
    assert_equal '/tmp/a.rb', entries[0].file
    assert_equal 1, entries[0].line       # 1-based
    assert_equal 7, entries[0].col        # char 6 + 1
    assert_equal 'method foozle', entries[1].text
    assert_equal '/tmp/b.rb', entries[1].file
  end

  def test_show_list_is_invoked_on_match
    @lsp.result = [{ name: 'X', kind: 5, location: {
      uri: 'file:///tmp/x.rb',
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
    } }]
    assert @editor.lsp_show_workspace_symbols('x')
    refute_nil @editor.list_view, 'expected listing overlay to be populated'
  end

  def test_command_rejects_empty_query_with_usage_message
    # ruby-lsp returns [] for an empty query rather than dumping the
    # whole index, so :LspWorkspaceSymbols with no arg would have been
    # a confusing "no matches" — the command layer guards against it.
    Rvim::Command.execute(@editor, Rvim::Command.parse(':LspWorkspaceSymbols'))
    assert_match(/usage :LspWorkspaceSymbols/, @editor.status_message.to_s)
    assert_empty @lsp.request_calls, 'request should NOT have been sent'
  end
end
