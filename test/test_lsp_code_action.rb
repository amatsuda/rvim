# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'fileutils'

class TestLspCodeActionClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_handle_response_stores_code_actions
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/codeAction', 'file:///x']
    msg = { id: 1, result: [
      { title: 'Fix spelling', kind: 'quickfix' },
      { title: 'Extract method' },
    ] }
    client.send(:handle_response, msg)
    assert_equal 2, client.last_code_actions_result.size
    assert_equal 'Fix spelling', client.last_code_actions_result.first[:title]
  end

  def test_code_action_clears_previous_and_sends_context
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_code_actions_result = [{}]
    range = { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }
    client.code_action('file:///x', range, diagnostics: [{ message: 'm' }])
    assert_nil client.last_code_actions_result
    assert_equal 'textDocument/codeAction', sent[:method]
    assert_equal range, sent[:params][:range]
    assert_equal 1, sent[:params][:context][:diagnostics].size
    assert_equal 1, sent[:params][:context][:triggerKind]
  end

  def test_execute_command_sends_command_and_args
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.execute_command('rubyLsp.someCmd', [{ foo: 1 }])
    assert_equal 'workspace/executeCommand', sent[:method]
    assert_equal 'rubyLsp.someCmd', sent[:params][:command]
    assert_equal [{ foo: 1 }], sent[:params][:arguments]
  end
end

class TestLspCodeActionManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_code_actions_result, :code_action_calls, :execute_command_calls

    def initialize
      @status = :running
      @code_action_calls = []
      @execute_command_calls = []
      @last_code_actions_result = nil
    end

    def code_action(uri, range, diagnostics: [])
      @code_action_calls << { uri: uri, range: range, diagnostics: diagnostics }
    end

    def execute_command(command, arguments = nil)
      @execute_command_calls << { command: command, arguments: arguments }
    end

    def diagnostics
      {
        'file:///x.rb' => [
          { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
            severity: 2, message: 'unused' },
          { range: { start: { line: 5, character: 0 }, end: { line: 5, character: 3 } },
            severity: 1, message: 'syntax' },
        ],
      }
    end
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

  def test_request_code_actions_filters_diagnostics_to_cursor_line
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
    assert @manager.request_code_actions(make_buffer)
    call = @client.code_action_calls.first
    assert_equal({ start: { line: 0, character: 2 }, end: { line: 0, character: 2 } }, call[:range])
    # Only the line-0 diagnostic is included; the line-5 one is filtered out.
    assert_equal 1, call[:diagnostics].size
    assert_equal 'unused', call[:diagnostics].first[:message]
  end

  def test_request_execute_command_forwards_to_client
    assert @manager.request_execute_command(make_buffer, 'rubyLsp.foo', [1])
    assert_equal({ command: 'rubyLsp.foo', arguments: [1] }, @client.execute_command_calls.first)
  end
end

class TestEditorLspCodeAction < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :code_action_returns, :result, :execute_calls,
                  :resolve_required, :resolve_result, :resolve_calls

    def initialize
      @code_action_returns = true
      @result = nil
      @execute_calls = []
      @resolve_required = false
      @resolve_result = nil
      @resolve_calls = []
    end

    def request_code_actions(_buf)
      @code_action_returns
    end

    def last_code_actions_result
      @result
    end

    def request_execute_command(_buf, command, arguments = nil)
      @execute_calls << { command: command, arguments: arguments }
      true
    end

    def code_action_resolve_required?(_buf); @resolve_required; end

    def request_code_action_resolve(_buf, action)
      @resolve_calls << action
      true
    end

    def last_code_action_resolve_result; @resolve_result; end

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
    @dir = Dir.mktmpdir('rvim-codeaction')
    @main = File.join(@dir, 'main.rb')
    File.write(@main, "def foo\n  bar\nend\n")

    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)
    @editor.open(@main)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_show_code_actions
  end

  def test_no_actions_status_message
    @lsp.result = []
    assert @editor.lsp_show_code_actions
    assert_match(/no code actions/, @editor.status_message.to_s)
    assert_nil @editor.instance_variable_get(:@last_code_actions)
  end

  def test_caches_and_lists_actions
    @lsp.result = [
      { title: 'Fix it', kind: 'quickfix',
        edit: { changes: {} } },
      { title: 'Refactor', kind: 'refactor' },
    ]
    assert @editor.lsp_show_code_actions
    assert_equal 2, @editor.instance_variable_get(:@last_code_actions).size
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/1\. Fix it/, body)
    assert_match(/2\. Refactor/, body)
  end

  def test_apply_returns_false_without_cache
    refute @editor.lsp_apply_code_action(1)
  end

  def test_apply_out_of_range
    @editor.instance_variable_set(:@last_code_actions, [{ title: 'x' }])
    refute @editor.lsp_apply_code_action(2)
    refute @editor.lsp_apply_code_action(0)
  end

  def test_apply_with_edit_mutates_buffer
    @editor.instance_variable_set(:@last_code_actions, [
      { title: 'Add space',
        edit: {
          changes: {
            "file://#{@main}" => [
              { range: { start: { line: 1, character: 0 }, end: { line: 1, character: 5 } },
                newText: 'BAZ' },
            ],
          },
        } },
    ])
    assert @editor.lsp_apply_code_action(1)
    assert_equal ['def foo', 'BAZ', 'end'], @editor.buffer_of_lines
    assert_match(/applied 'Add space'/, @editor.status_message.to_s)
  end

  def test_apply_with_command_sends_executeCommand
    @editor.instance_variable_set(:@last_code_actions, [
      { title: 'Run codemod',
        command: { command: 'rubyLsp.runCodemod', arguments: ['foo'] } },
    ])
    assert @editor.lsp_apply_code_action(1)
    assert_equal 'rubyLsp.runCodemod', @lsp.execute_calls.first[:command]
    assert_equal ['foo'], @lsp.execute_calls.first[:arguments]
  end

  def test_apply_resolves_unresolved_action_before_applying
    # Server returned an action with only :data, advertised resolve support.
    @lsp.resolve_required = true
    @lsp.resolve_result = {
      title: 'Create Attribute Reader',
      edit: {
        changes: {
          "file://#{@main}" => [
            { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
              newText: "  attr_reader :ivar\n" },
          ],
        },
      },
    }
    @editor.instance_variable_set(:@last_code_actions, [
      { title: 'Create Attribute Reader', data: { uri: 'file:///x', some: 'meta' } },
    ])
    assert @editor.lsp_apply_code_action(1)
    # The resolve request was sent with the original (unresolved) action.
    assert_equal 1, @lsp.resolve_calls.size
    assert_equal 'Create Attribute Reader', @lsp.resolve_calls.first[:title]
    # The resolved action's edit was applied — first line is the new
    # attr_reader; the original "def foo" got pushed to line 1.
    assert_equal '  attr_reader :ivar', @editor.buffer_of_lines[0]
    assert_equal 'def foo', @editor.buffer_of_lines[1]
  end

  def test_apply_with_edit_and_command_does_both
    @editor.instance_variable_set(:@last_code_actions, [
      { title: 'Compound',
        edit: { changes: { "file://#{@main}" => [
          { range: { start: { line: 0, character: 4 }, end: { line: 0, character: 7 } }, newText: 'XXX' },
        ] } },
        command: { command: 'rubyLsp.followUp' } },
    ])
    assert @editor.lsp_apply_code_action(1)
    assert_equal ['def XXX', '  bar', 'end'], @editor.buffer_of_lines
    assert_equal 'rubyLsp.followUp', @lsp.execute_calls.first[:command]
  end
end
