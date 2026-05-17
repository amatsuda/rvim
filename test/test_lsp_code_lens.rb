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
    # Title is prefixed with a 1-based index so the user can pick the
    # lens to run via `:LspCodeLens 2`.
    assert_equal '1. ▶ Run', entries[0].text
    assert_equal 1, entries[0].line # 0 + 1 (1-based)
    assert_equal 1, entries[0].col  # 0 + 1
    assert_equal '3. ▶ Run Test: test_hello', entries[2].text
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

class TestEditorLspExecuteCodeLens < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :execute_calls

    def initialize
      @execute_calls = []
    end

    def request_execute_command(_buf, name, args)
      @execute_calls << { name: name, args: args }
      true
    end

    def flush_changes(_buf); false; end
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

    @buf = Rvim::Buffer.new(1, '/tmp/test.rb')
    @buf.lines = ['def test_foo', 'end']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@filepath, '/tmp/test.rb')

    # Pretend the user just ran :LspCodeLens.
    @editor.instance_variable_set(:@last_code_lenses, [
      { range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } },
        command: { title: '▶ Run', command: 'rubyLsp.runTest',
                   arguments: ['/tmp/test.rb', 'FooTest', 'echo from-shell', {}, 'FooTest'] } },
      { range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } },
        command: { title: 'Debug', command: 'rubyLsp.debugTest', arguments: [] } },
      { range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } },
        command: { title: 'Server cmd', command: 'gopls.test', arguments: ['arg1'] } },
    ])

    # Avoid actually shelling out — capture the shell command instead.
    @ran = nil
    captured = ->(c) { @ran = c }
    @editor.define_singleton_method(:run_code_lens_shell_command) { |c| captured.call(c) }
  end

  def test_returns_false_when_no_cache
    @editor.instance_variable_set(:@last_code_lenses, nil)
    refute @editor.lsp_execute_code_lens(1)
  end

  def test_returns_false_when_index_out_of_range
    refute @editor.lsp_execute_code_lens(0)
    refute @editor.lsp_execute_code_lens(99)
  end

  def test_runs_rubyLsp_runTest_via_shell_args2
    assert @editor.lsp_execute_code_lens(1)
    assert_equal 'echo from-shell', @ran
    assert_match(/ran '▶ Run'/, @editor.status_message.to_s)
  end

  def test_debug_lens_not_supported
    assert @editor.lsp_execute_code_lens(2)
    assert_nil @ran, 'should NOT shell out for debug'
    assert_match(/debug lens not supported/, @editor.status_message.to_s)
  end

  def test_falls_back_to_workspace_executeCommand_for_other_servers
    assert @editor.lsp_execute_code_lens(3)
    assert_nil @ran
    assert_equal 1, @lsp.execute_calls.size
    assert_equal 'gopls.test', @lsp.execute_calls.first[:name]
    assert_equal ['arg1'], @lsp.execute_calls.first[:args]
  end

  def test_empty_shell_args2_reports_no_command
    @editor.instance_variable_get(:@last_code_lenses)[0][:command][:arguments][2] = ''
    @editor.lsp_execute_code_lens(1)
    assert_match(/no command to run/, @editor.status_message.to_s)
    assert_nil @ran
  end
end
