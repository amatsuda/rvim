# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'fileutils'

class TestLspRenameClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_handle_response_stores_workspace_edit
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/rename', 'file:///x']
    msg = { id: 1, result: { changes: { 'file:///x' => [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } }, newText: 'y' },
    ] } } }
    client.send(:handle_response, msg)
    assert_equal Hash, client.last_rename_result[:changes].class
  end

  def test_rename_clears_previous_result_and_sends_newName
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_rename_result = { changes: {} }
    client.rename('file:///x', 3, 5, 'new_name')
    assert_nil client.last_rename_result
    assert_equal 'textDocument/rename', sent[:method]
    assert_equal({ line: 3, character: 5 }, sent[:params][:position])
    assert_equal 'new_name', sent[:params][:newName]
  end
end

class TestLspRenameManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_rename_result, :rename_calls

    def initialize
      @status = :running
      @rename_calls = []
      @last_rename_result = nil
    end

    def rename(uri, line, character, new_name)
      @rename_calls << { uri: uri, line: line, character: character, new_name: new_name }
    end

    def diagnostics; {}; end
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

  def test_request_rename_sends_position_and_name
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 4)
    assert @manager.request_rename(make_buffer, 'y')
    assert_equal({ uri: 'file:///x.rb', line: 0, character: 4, new_name: 'y' },
                 @client.rename_calls.first)
  end

  def test_request_rename_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_rename(make_buffer, 'y')
  end
end

class TestEditorLspRenameSymbol < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result, :prepare_required, :prepare_result

    def initialize
      @request_returns = true
      @result = nil
      @prepare_required = false
      @prepare_result = nil
    end

    def request_rename(_buf, _name)
      @request_returns
    end

    def last_rename_result
      @result
    end

    def rename_prepare_required?(_buf)
      @prepare_required
    end

    def request_prepare_rename(_buf)
      true
    end

    def last_prepare_rename_result
      @prepare_result
    end

    def flush_changes(_buf); false; end
    def pending_for?(_); false; end
    def did_open(_buf); end
    def did_close(_buf); end
    def note_change(_buf); false; end
    def maybe_pull_diagnostics(_buf); false; end
    def pump; end
    def diagnostic_signs(_); {}; end
    def diagnostic_ranges(_); {}; end
  end

  def setup
    @dir = Dir.mktmpdir('rvim-rename')
    @main = File.join(@dir, 'main.rb')
    @other = File.join(@dir, 'other.rb')
    File.write(@main, "def foo\n  bar\nend\n")
    File.write(@other, "class Other\n  def bar; end\nend\n")

    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)
    # Polling loops sleep 0.02s between checks; stub to keep tests fast
    # while still letting Time.now move forward to hit the deadline.
    @editor.define_singleton_method(:sleep) { |_| nil }

    @editor.open(@main)
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def test_returns_false_on_empty_name
    refute @editor.lsp_rename_symbol('')
    refute @editor.lsp_rename_symbol('   ')
  end

  def test_aborts_when_prepareRename_returns_nil
    @lsp.prepare_required = true
    @lsp.prepare_result = nil
    # If prepare fails, we never even call rename.
    assert @editor.lsp_rename_symbol('y')
    assert_match(/cannot rename at/, @editor.status_message.to_s)
    # Current buffer is untouched.
    assert_equal ['def foo', '  bar', 'end'], @editor.buffer_of_lines
  end

  def test_proceeds_when_prepareRename_returns_range
    @lsp.prepare_required = true
    @lsp.prepare_result = { start: { line: 1, character: 2 }, end: { line: 1, character: 5 } }
    @lsp.result = {
      changes: {
        "file://#{@main}" => [
          { range: { start: { line: 1, character: 2 }, end: { line: 1, character: 5 } }, newText: 'baz' },
        ],
      },
    }
    assert @editor.lsp_rename_symbol('baz')
    assert_equal ['def foo', '  baz', 'end'], @editor.buffer_of_lines
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_rename_symbol('x')
  end

  def test_no_edits_status_message
    @lsp.result = { changes: {} }
    assert @editor.lsp_rename_symbol('x')
    assert_match(/produced no edits/, @editor.status_message.to_s)
  end

  def test_applies_changes_to_current_buffer_in_memory
    # Rename `bar` → `baz` in main.rb (the current buffer)
    @lsp.result = {
      changes: {
        "file://#{@main}" => [
          { range: { start: { line: 1, character: 2 }, end: { line: 1, character: 5 } }, newText: 'baz' },
        ],
      },
    }
    assert @editor.lsp_rename_symbol('baz')
    assert_equal ['def foo', '  baz', 'end'], @editor.buffer_of_lines
    assert @editor.modified, 'current buffer should be marked modified'
    # File on disk untouched until :w
    assert_equal "def foo\n  bar\nend\n", File.read(@main)
  end

  def test_applies_changes_to_other_file_on_disk
    # other.rb is NOT open as a buffer; edits go straight to disk.
    @lsp.result = {
      changes: {
        "file://#{@other}" => [
          { range: { start: { line: 1, character: 6 }, end: { line: 1, character: 9 } }, newText: 'baz' },
        ],
      },
    }
    assert @editor.lsp_rename_symbol('baz')
    assert_equal "class Other\n  def baz; end\nend\n", File.read(@other)
  end

  def test_handles_documentChanges_form
    # documentChanges takes precedence per LSP spec; changes is ignored
    # when both are present.
    @lsp.result = {
      documentChanges: [{
        textDocument: { uri: "file://#{@main}", version: 1 },
        edits: [
          { range: { start: { line: 0, character: 4 }, end: { line: 0, character: 7 } }, newText: 'xxx' },
        ],
      }],
    }
    assert @editor.lsp_rename_symbol('xxx')
    assert_equal ['def xxx', '  bar', 'end'], @editor.buffer_of_lines
  end

  def test_skips_non_text_documentChanges
    # File create/rename/delete operations come in as {kind: ...} hashes
    # without :edits — we currently skip them.
    @lsp.result = {
      documentChanges: [
        { kind: 'create', uri: "file://#{@other}.new" },
        {
          textDocument: { uri: "file://#{@main}", version: 1 },
          edits: [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } }, newText: 'DEF' }],
        },
      ],
    }
    assert @editor.lsp_rename_symbol('DEF')
    assert_equal ['DEF foo', '  bar', 'end'], @editor.buffer_of_lines
  end
end
