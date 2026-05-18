# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# textDocument/documentLink layers:
#   - Client request shape + handle_response stashing
#   - Manager wiring + capability gate
#   - Editor lsp_show_document_links populates quickfix; lsp_goto_link
#     finds the link covering the cursor and opens its target

class TestLspDocumentLinkClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_document_link_clears_previous_and_sends_uri_only
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_document_link_result = [{}]
    client.document_link('file:///x.rb')
    assert_nil client.last_document_link_result
    assert_equal 'textDocument/documentLink', sent[:method]
    assert_equal({ uri: 'file:///x.rb' }, sent[:params][:textDocument])
  end

  def test_handle_response_stashes_link_array
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/documentLink', 'file:///x']
    msg = { id: 1, result: [
      { range: { start: { line: 0, character: 2 }, end: { line: 0, character: 30 } },
        target: 'file:///gems/json/json.rb#42', tooltip: 'Jump to json.rb#42' },
    ] }
    client.send(:handle_response, msg)
    assert_equal 1, client.last_document_link_result.size
    assert_equal 'Jump to json.rb#42', client.last_document_link_result.first[:tooltip]
  end
end

class TestLspDocumentLinkManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :capabilities, :last_document_link_result, :calls

    def initialize
      @status = :running
      @capabilities = { documentLinkProvider: {} }
      @calls = []
    end

    def document_link(uri); @calls << uri; end
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
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['# source://json'] }
  end

  def test_request_calls_client
    assert @manager.request_document_link(make_buffer)
    assert_equal ['file:///x.rb'], @client.calls
  end

  def test_request_unsupported_without_capability
    @client.capabilities = {}
    assert_equal :unsupported, @manager.request_document_link(make_buffer)
    assert_empty @client.calls
  end
end

class TestEditorLspDocumentLink < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result

    def initialize
      @request_returns = true
      @result = nil
    end

    def flush_changes(_buf); false; end
    def request_document_link(_buf); @request_returns; end
    def last_document_link_result; @result; end

    def pending_for?(_); false; end
    def pump; end
    def diagnostic_signs(_); {}; end
    def diagnostic_ranges(_); {}; end
    def diagnostics_for(_); []; end
    def document_highlights_by_line(_); {}; end
    def inlay_hints_by_line(_); {}; end
    def semantic_tokens_by_line(_); {}; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = ['# source://json/json/json.rb#42', 'def foo', 'end']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@filepath, '/tmp/x.rb')
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 5)
  end

  # ----- list -----

  def test_show_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_show_document_links
  end

  def test_show_surfaces_unsupported_status
    @lsp.request_returns = :unsupported
    assert @editor.lsp_show_document_links
    assert_match(/does not support documentLink/, @editor.status_message.to_s)
  end

  def test_show_no_links_status
    @lsp.result = []
    assert @editor.lsp_show_document_links
    assert_match(/no document links/, @editor.status_message.to_s)
  end

  def test_show_populates_quickfix_with_index_prefix
    @lsp.result = [
      { range: { start: { line: 0, character: 2 }, end: { line: 0, character: 30 } },
        target: 'file:///gems/json/json.rb#42', tooltip: 'Jump to json.rb#42' },
      { range: { start: { line: 2, character: 0 }, end: { line: 2, character: 5 } },
        target: 'file:///gems/other.rb#7' }, # no tooltip → uses target
    ]
    @editor.lsp_show_document_links
    entries = @editor.quickfix.entries
    assert_equal 2, entries.size
    assert_equal '1. Jump to json.rb#42', entries[0].text
    assert_match(/2\. file:\/\/\/gems\/other\.rb#7/, entries[1].text)
    assert_equal 1, entries[0].line # 0 + 1
    assert_equal 3, entries[0].col  # 2 + 1
  end

  # ----- goto at cursor -----

  def test_goto_no_link_status
    @lsp.result = []
    assert @editor.lsp_goto_document_link_at_cursor
    assert_match(/no document link at cursor/, @editor.status_message.to_s)
  end

  def test_goto_opens_file_uri_with_line_fragment
    @lsp.result = [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 31 } },
        target: 'file:///tmp/other.rb#3' },
    ]
    # Stub open() so we don't try to actually load the file.
    opened = nil
    @editor.define_singleton_method(:open) { |p| opened = p }
    @editor.lsp_goto_document_link_at_cursor
    assert_equal '/tmp/other.rb', opened
    assert_equal 2, @editor.line_index # fragment 3 -> line 2 (0-based)
    assert_match(/opened/, @editor.status_message.to_s)
  end

  def test_goto_skips_open_when_same_file
    @lsp.result = [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 31 } },
        target: 'file:///tmp/x.rb#3' },
    ]
    open_called = false
    @editor.define_singleton_method(:open) { |_| open_called = true }
    @editor.lsp_goto_document_link_at_cursor
    refute open_called, 'same file → no reopen'
    assert_equal 2, @editor.line_index
  end

  def test_goto_http_target_shows_url_in_status_bar
    @lsp.result = [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 31 } },
        target: 'https://example.com/x' },
    ]
    @editor.lsp_goto_document_link_at_cursor
    assert_match(%r{link -> https://example\.com/x}, @editor.status_message.to_s)
  end

  def test_goto_link_with_no_target_status
    @lsp.result = [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 31 } } },
    ]
    @editor.lsp_goto_document_link_at_cursor
    assert_match(/no target/, @editor.status_message.to_s)
  end
end
