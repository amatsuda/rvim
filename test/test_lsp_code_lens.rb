# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# textDocument/codeLens covers three layers:
#   - Client request shape + handle_response stashing
#   - Manager wiring + capability gate
#   - Editor lsp_show_code_lenses populates quickfix one row per lens

class TestLspCodeLensClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_code_lens_clears_and_sends_uri_only
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_code_lens_result = [{}]
    client.code_lens('file:///x.rb')
    assert_nil client.last_code_lens_result
    assert_equal 'textDocument/codeLens', sent[:method]
    assert_equal({ uri: 'file:///x.rb' }, sent[:params][:textDocument])
    refute sent[:params].key?(:position)
  end

  def test_handle_response_stashes_lens_array
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/codeLens', 'file:///x']
    msg = { id: 1, result: [
      { range: { start: { line: 0, character: 0 }, end: { line: 5, character: 3 } },
        command: { title: '▶ Run', command: 'rubyLsp.runTest', arguments: [] } },
    ] }
    client.send(:handle_response, msg)
    assert_equal 1, client.last_code_lens_result.size
    assert_equal '▶ Run', client.last_code_lens_result.first.dig(:command, :title)
  end
end

class TestLspCodeLensManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :capabilities, :last_code_lens_result, :calls

    def initialize
      @status = :running
      @capabilities = { codeLensProvider: { resolveProvider: true } }
      @calls = []
    end

    def code_lens(uri); @calls << uri; end
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

  def test_request_calls_client
    assert @manager.request_code_lens(make_buffer)
    assert_equal ['file:///x.rb'], @client.calls
  end

  def test_request_unsupported_without_capability
    @client.capabilities = {}
    assert_equal :unsupported, @manager.request_code_lens(make_buffer)
    assert_empty @client.calls
  end
end

class TestEditorLspShowCodeLenses < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result

    def initialize
      @request_returns = true
      @result = nil
    end

    def flush_changes(_buf); false; end
    def request_code_lens(_buf); @request_returns; end
    def last_code_lens_result; @result; end

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

    @buf = Rvim::Buffer.new(1, '/tmp/test.rb')
    @buf.lines = ['class GreeterTest', '  def test_hello', '  end', 'end']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@filepath, '/tmp/test.rb')
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_show_code_lenses
  end

  def test_surfaces_unsupported_status
    @lsp.request_returns = :unsupported
    assert @editor.lsp_show_code_lenses
    assert_match(/does not support codeLens/, @editor.status_message.to_s)
  end

  def test_no_lenses_status
    @lsp.result = []
    assert @editor.lsp_show_code_lenses
    assert_match(/no code lenses/, @editor.status_message.to_s)
  end

  def test_skips_lenses_without_title
    # Per spec a lens with no `command` requires a separate resolve;
    # since we don't bother, those silently drop out.
    @lsp.result = [
      { range: { start: { line: 0, character: 0 }, end: { line: 3, character: 3 } } },
    ]
    @editor.lsp_show_code_lenses
    assert_match(/no code lenses/, @editor.status_message.to_s)
  end

  def test_populates_quickfix_with_one_entry_per_lens
    @lsp.result = [
      { range: { start: { line: 0, character: 0 }, end: { line: 3, character: 3 } },
        command: { title: '▶ Run' } },
      { range: { start: { line: 0, character: 0 }, end: { line: 3, character: 3 } },
        command: { title: '▶ Run In Terminal' } },
      { range: { start: { line: 1, character: 2 }, end: { line: 2, character: 5 } },
        command: { title: '▶ Run Test: test_hello' } },
    ]
    assert @editor.lsp_show_code_lenses
    entries = @editor.quickfix.entries
    assert_equal 3, entries.size
    assert_equal '▶ Run', entries[0].text
    assert_equal 1, entries[0].line # 0 + 1 (1-based)
    assert_equal 1, entries[0].col  # 0 + 1
    assert_equal '▶ Run Test: test_hello', entries[2].text
    assert_equal 2, entries[2].line # 1 + 1
    assert_equal 3, entries[2].col  # 2 + 1
    assert_equal '/tmp/test.rb', entries[0].file
  end

  def test_show_list_is_invoked_on_match
    @lsp.result = [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        command: { title: '▶ Run' } },
    ]
    @editor.lsp_show_code_lenses
    refute_nil @editor.list_view, 'expected listing overlay to be populated'
  end
end
