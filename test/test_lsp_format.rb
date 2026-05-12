# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

class TestLspFormatClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_handle_response_stores_text_edits
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/formatting', 'file:///x']
    msg = { id: 1, result: [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 5 } }, newText: 'hello' },
    ] }
    client.send(:handle_response, msg)
    assert_equal 1, client.last_formatting_result.size
    assert_equal 'hello', client.last_formatting_result.first[:newText]
  end

  def test_formatting_clears_previous_and_sends_options
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_formatting_result = [{}]
    client.formatting('file:///x', tab_size: 4, insert_spaces: false)
    assert_nil client.last_formatting_result
    assert_equal 'textDocument/formatting', sent[:method]
    assert_equal({ tabSize: 4, insertSpaces: false }, sent[:params][:options])
  end
end

class TestLspFormatManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_formatting_result, :format_calls

    def initialize
      @status = :running
      @format_calls = []
      @last_formatting_result = nil
    end

    def formatting(uri, tab_size: 2, insert_spaces: true)
      @format_calls << { uri: uri, tab_size: tab_size, insert_spaces: insert_spaces }
    end

    def diagnostics; {}; end
    def flush_changes(_buf); false; end
    def pending_for?(_); false; end
    def pump; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:tabstop, 4)
    @editor.settings.set(:expandtab, true)
    @manager = Rvim::Lsp::Manager.new(@editor)
    @manager.define_singleton_method(:filetype_for) { |_| :ruby }
    @manager.define_singleton_method(:buffer_uri) { |_| 'file:///x.rb' }
    @client = FakeClient.new
    @manager.instance_variable_set(:@clients, { ruby: @client })
  end

  def make_buffer
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['x = 1'] }
  end

  def test_request_formatting_sends_options_from_settings
    assert @manager.request_formatting(make_buffer)
    call = @client.format_calls.first
    assert_equal 4, call[:tab_size]
    assert_equal true, call[:insert_spaces]
  end

  def test_request_formatting_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_formatting(make_buffer)
  end
end

class TestEditorLspFormatBuffer < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result

    def initialize
      @request_returns = true
      @result = nil
    end

    def request_formatting(_buf)
      @request_returns
    end

    def last_formatting_result
      @result
    end

    def did_open(_buf); end
    def did_close(_buf); end
    def note_change(_buf); false; end
    def maybe_pull_diagnostics(_buf); false; end
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
    @buf.lines = ['def foo', '  x=1', 'end']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_format_buffer
  end

  def test_no_op_when_result_empty
    @lsp.result = []
    assert @editor.lsp_format_buffer
    assert_match(/no formatting changes/, @editor.status_message.to_s)
    assert_equal ['def foo', '  x=1', 'end'], @editor.buffer_of_lines
  end

  def test_replaces_full_document_via_single_edit
    # ruby-lsp's typical full-doc edit: range covers whole doc, newText
    # is the formatted version.
    @lsp.result = [{
      range: { start: { line: 0, character: 0 }, end: { line: 2, character: 3 } },
      newText: "def foo\n  x = 1\nend",
    }]
    assert @editor.lsp_format_buffer
    assert_equal ['def foo', '  x = 1', 'end'], @editor.buffer_of_lines
    assert @editor.modified
  end

  def test_applies_single_line_edit
    @lsp.result = [{
      range: { start: { line: 1, character: 2 }, end: { line: 1, character: 5 } },
      newText: 'x = 1',
    }]
    assert @editor.lsp_format_buffer
    assert_equal ['def foo', '  x = 1', 'end'], @editor.buffer_of_lines
  end

  def test_applies_multiple_edits_in_descending_order
    # Two single-line edits. If we applied in document order, the second
    # edit's offset would be wrong. Reverse-sorting handles this.
    @editor.instance_variable_set(:@buffer_of_lines, ['a=1', 'b=2', 'c=3'])
    @lsp.result = [
      { range: { start: { line: 0, character: 1 }, end: { line: 0, character: 2 } }, newText: ' = ' },
      { range: { start: { line: 2, character: 1 }, end: { line: 2, character: 2 } }, newText: ' = ' },
    ]
    assert @editor.lsp_format_buffer
    assert_equal ['a = 1', 'b=2', 'c = 3'], @editor.buffer_of_lines
  end

  def test_no_change_when_text_identical
    @lsp.result = [{
      range: { start: { line: 0, character: 0 }, end: { line: 2, character: 3 } },
      newText: "def foo\n  x=1\nend",
    }]
    assert @editor.lsp_format_buffer
    assert_match(/no formatting changes/, @editor.status_message.to_s)
  end

  def test_handles_end_of_document_range
    # Range with end.line == lines.size, end.character == 0 — vim/LSP
    # convention for "to the end of the document".
    @lsp.result = [{
      range: { start: { line: 0, character: 0 }, end: { line: 3, character: 0 } },
      newText: "ok\n",
    }]
    assert @editor.lsp_format_buffer
    assert_equal ['ok', ''], @editor.buffer_of_lines
  end
end
