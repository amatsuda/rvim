# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

class TestLspCompletionClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_handle_response_stores_completion_item_array
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/completion', 'file:///x']
    msg = { id: 1, result: [{ label: 'foo' }, { label: 'bar' }] }
    client.send(:handle_response, msg)
    assert_equal 2, client.last_completion_result.size
  end

  def test_handle_response_stores_completion_list
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/completion', 'file:///x']
    msg = { id: 1, result: { isIncomplete: false, items: [{ label: 'foo' }] } }
    client.send(:handle_response, msg)
    assert_equal false, client.last_completion_result[:isIncomplete]
    assert_equal 1, client.last_completion_result[:items].size
  end

  def test_completion_clears_previous_result_and_sends_position
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_completion_result = [{}]
    client.completion('file:///x', 3, 7)
    assert_nil client.last_completion_result
    assert_equal 'textDocument/completion', sent[:method]
    assert_equal({ line: 3, character: 7 }, sent[:params][:position])
  end
end

class TestLspCompletionManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_completion_result, :completion_calls

    def initialize
      @status = :running
      @completion_calls = []
      @last_completion_result = nil
    end

    def completion(uri, line, character)
      @completion_calls << { uri: uri, line: line, character: character }
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

  def test_request_completion_sends_position
    @editor.instance_variable_set(:@line_index, 2)
    @editor.instance_variable_set(:@byte_pointer, 5)
    assert @manager.request_completion(make_buffer)
    assert_equal({ uri: 'file:///x.rb', line: 2, character: 5 }, @client.completion_calls.first)
  end

  def test_request_completion_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_completion(make_buffer)
  end
end

class TestEditorLspCompletion < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result

    def initialize
      @request_returns = true
      @result = nil
    end

    def request_completion(_buf)
      @request_returns
    end

    def last_completion_result
      @result
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
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = [+'fo']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
  end

  def test_no_lsp_candidates_when_disabled
    @editor.settings.set(:lsp_enabled, false)
    assert_equal [], @editor.send(:collect_lsp_completion_candidates, 'fo')
  end

  def test_empty_response_yields_empty_candidates
    @lsp.result = []
    assert_equal [], @editor.send(:collect_lsp_completion_candidates, 'fo')
  end

  def test_filters_by_prefix
    @lsp.result = [
      { label: 'foo' }, { label: 'foobar' }, { label: 'bar' },
    ]
    cands = @editor.send(:collect_lsp_completion_candidates, 'fo')
    assert_equal %w[foo foobar], cands
  end

  def test_handles_completion_list_form
    @lsp.result = {
      isIncomplete: false,
      items: [{ label: 'foo' }, { label: 'foozle' }],
    }
    cands = @editor.send(:collect_lsp_completion_candidates, 'fo')
    assert_equal %w[foo foozle], cands
  end

  def test_prefers_insertText_over_label
    @lsp.result = [
      { label: 'foo (alias)', insertText: 'foo' },
      { label: 'foobar', insertText: 'foobar' },
    ]
    cands = @editor.send(:collect_lsp_completion_candidates, 'fo')
    assert_equal %w[foo foobar], cands
  end

  def test_start_completion_merges_lsp_and_keyword_with_lsp_first
    # Buffer has `fooled` as a keyword; LSP returns `foo` and `foobar`.
    @editor.instance_variable_set(:@buffer_of_lines, ['fooled', 'fo'])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @lsp.result = [{ label: 'foo' }, { label: 'foobar' }]
    @editor.send(:start_completion, +1)
    cands = @editor.instance_variable_get(:@completion_candidates)
    # LSP candidates appear first; keyword candidates filtered to those
    # not already in the LSP set follow.
    assert_equal %w[foo foobar fooled], cands
  end

  def test_start_completion_falls_back_to_keyword_when_lsp_empty
    @editor.instance_variable_set(:@buffer_of_lines, %w[foobar fooled fo])
    @editor.instance_variable_set(:@line_index, 2)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @lsp.result = []
    @editor.send(:start_completion, +1)
    cands = @editor.instance_variable_get(:@completion_candidates)
    refute_nil cands
    assert(cands.include?('foobar') || cands.include?('fooled'),
            "expected fallback to keyword candidates, got #{cands.inspect}")
  end

  def test_start_completion_inserts_first_candidate_into_buffer
    @lsp.result = [{ label: 'foobar' }, { label: 'foozle' }]
    @editor.send(:start_completion, +1)
    assert_equal 'foobar', @editor.buffer_of_lines[0]
    assert_equal 6, @editor.byte_pointer
  end
end
