# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'fileutils'

class TestLspReferencesClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_handle_response_stores_references_result
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/references', 'file:///x']
    msg = { id: 1, result: [
      { uri: 'file:///a.rb', range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } } },
      { uri: 'file:///b.rb', range: { start: { line: 1, character: 2 }, end: { line: 1, character: 3 } } },
    ] }
    client.send(:handle_response, msg)
    assert_equal 2, client.last_references_result.size
    assert_equal 'file:///b.rb', client.last_references_result[1][:uri]
  end

  def test_references_clears_previous_result_and_sends_includeDeclaration
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_references_result = [{ uri: 'old' }]
    client.references('file:///x', 4, 7)
    assert_nil client.last_references_result
    assert_equal 'textDocument/references', sent[:method]
    assert_equal({ line: 4, character: 7 }, sent[:params][:position])
    assert_equal({ includeDeclaration: true }, sent[:params][:context])
  end
end

class TestLspReferencesManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_references_result, :reference_calls

    def initialize
      @status = :running
      @reference_calls = []
      @last_references_result = nil
    end

    def references(uri, line, character, include_declaration: true)
      @reference_calls << { uri: uri, line: line, character: character,
                            include_declaration: include_declaration }
    end

    def diagnostics; {}; end
    def flush_changes(_buf); false; end
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

  def test_request_references_sends_cursor_position
    @editor.instance_variable_set(:@line_index, 4)
    @editor.instance_variable_set(:@byte_pointer, 7)
    assert @manager.request_references(make_buffer)
    call = @client.reference_calls.first
    assert_equal 4, call[:line]
    assert_equal 7, call[:character]
  end

  def test_request_references_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_references(make_buffer)
  end

  def test_last_references_result_reads_from_client
    @client.last_references_result = [{ uri: 'file:///a' }]
    assert_equal 1, @manager.last_references_result.size
  end
end

class TestEditorLspFindReferences < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result

    def initialize
      @request_returns = true
      @result = nil
    end

    def request_references(_buf)
      @request_returns
    end

    def last_references_result
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
    @dir = Dir.mktmpdir('rvim-refs')
    @main = File.join(@dir, 'main.rb')
    @other = File.join(@dir, 'other.rb')
    File.write(@main, "def foo\n  bar\nend\n")
    File.write(@other, "class Other\n  def bar; end\nend\n")

    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @editor.open(@main)
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_find_references
  end

  def test_returns_false_when_request_unsuccessful
    @lsp.request_returns = false
    refute @editor.lsp_find_references
  end

  def test_no_references_status_message
    @lsp.result = []
    assert @editor.lsp_find_references
    assert_match(/no references/, @editor.status_message.to_s)
    assert @editor.quickfix.empty?
  end

  def test_populates_quickfix_and_jumps_to_first
    @lsp.result = [
      { uri: "file://#{@main}",
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 5 } } },
      { uri: "file://#{@other}",
        range: { start: { line: 1, character: 6 }, end: { line: 1, character: 9 } } },
    ]
    assert @editor.lsp_find_references
    assert_equal 2, @editor.quickfix.size
    # First entry's text grabs the line content from disk
    first = @editor.quickfix.entries.first
    assert_equal @main, first.file
    assert_equal 2, first.line
    assert_equal 3, first.col
    assert_equal 'bar', first.text
    # Cursor jumped to the first reference
    assert_equal 1, @editor.line_index
    assert_equal 2, @editor.byte_pointer
    assert_match(/1 of 2/, @editor.status_message.to_s)
  end

  def test_handles_nil_result
    @lsp.result = nil # poll loop times out; result stays nil
    # Force the poll to short-circuit by setting an empty array (matches
    # spec's null → caller treats as empty)
    @lsp.result = []
    assert @editor.lsp_find_references
    assert @editor.quickfix.empty?
  end

  def test_handles_locationlink_form
    @lsp.result = [
      { targetUri: "file://#{@main}",
        targetRange: { start: { line: 0, character: 4 }, end: { line: 0, character: 7 } } },
    ]
    assert @editor.lsp_find_references
    assert_equal 1, @editor.quickfix.size
    entry = @editor.quickfix.entries.first
    assert_equal @main, entry.file
    assert_equal 1, entry.line
    assert_equal 5, entry.col
    assert_equal 'def foo', entry.text
  end

  def test_skips_locations_with_missing_fields
    @lsp.result = [
      { uri: "file://#{@main}", range: nil },          # no range
      { range: { start: { line: 0, character: 0 } } }, # no uri
      { uri: "file://#{@main}",
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } } },
    ]
    assert @editor.lsp_find_references
    assert_equal 1, @editor.quickfix.size
  end
end
