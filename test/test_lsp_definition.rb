# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

class TestLspDefinitionClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new) # not used; we exercise handle_response directly
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_handle_response_stores_definition_result
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/definition', 'file:///x']
    msg = { id: 1, result: { uri: 'file:///y.rb',
                             range: { start: { line: 3, character: 0 }, end: { line: 3, character: 5 } } } }
    client.send(:handle_response, msg)
    assert_equal 'file:///y.rb', client.last_definition_result[:uri]
  end

  def test_handle_response_stores_array_result
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/definition', 'file:///x']
    msg = { id: 1, result: [{ uri: 'file:///y.rb',
                              range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } } }] }
    client.send(:handle_response, msg)
    assert_equal 1, client.last_definition_result.size
  end

  def test_handle_response_stores_null_result
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/definition', 'file:///x']
    client.send(:handle_response, { id: 1, result: nil })
    # Stored verbatim as nil (caller treats nil as "no definition"); we only
    # check that the call doesn't blow up.
    assert_nil client.last_definition_result
  end

  def test_definition_clears_previous_result
    client = make_client
    # Stub the network so request() doesn't try to write
    client.define_singleton_method(:send_message) { |_| nil }
    client.last_definition_result = { uri: 'old' }
    client.definition('file:///x', 0, 0)
    assert_nil client.last_definition_result
  end
end

class TestLspDefinitionManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_definition_result, :definition_calls

    def initialize
      @status = :running
      @definition_calls = []
      @last_definition_result = nil
    end

    def definition(uri, line, character)
      @definition_calls << { uri: uri, line: line, character: character }
      # caller (Manager#request_definition) doesn't await — leave result nil
      # until the test sets it manually
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
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['x = 1'] }
  end

  def test_request_definition_sends_position_from_editor_cursor
    buf = make_buffer
    @editor.instance_variable_set(:@line_index, 4)
    @editor.instance_variable_set(:@byte_pointer, 7)
    assert @manager.request_definition(buf)
    call = @client.definition_calls.first
    assert_equal 4, call[:line]
    assert_equal 7, call[:character]
    assert_equal 'file:///x.rb', call[:uri]
  end

  def test_request_definition_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_definition(make_buffer)
  end

  def test_request_definition_returns_false_when_not_running
    @client.status = :starting
    refute @manager.request_definition(make_buffer)
    assert_empty @client.definition_calls
  end

  def test_last_definition_result_reads_from_client
    @client.last_definition_result = { uri: 'file:///y.rb' }
    assert_equal 'file:///y.rb', @manager.last_definition_result[:uri]
  end
end

class TestEditorLspJumpToDefinition < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_definition_returns, :result

    def initialize
      @request_definition_returns = true
      @result = nil
    end

    def request_definition(_buffer)
      @request_definition_returns
    end

    def last_definition_result
      @result
    end

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
    @buf.lines = ['x = 1', 'y = 2']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.instance_variable_set(:@filepath, '/tmp/x.rb')
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_jump_to_definition
  end

  def test_returns_false_when_request_unsuccessful
    @lsp.request_definition_returns = false
    refute @editor.lsp_jump_to_definition
  end

  def test_status_message_when_no_definition
    @lsp.result = nil
    # Make the result accessor return nil immediately so the loop short-
    # circuits at the deadline. The poll uses Time.now; bypass by setting
    # an empty array as result so the loop exits.
    @lsp.result = []
    assert @editor.lsp_jump_to_definition
    assert_match(/no definition/, @editor.status_message.to_s)
  end

  def test_jumps_to_same_file_target
    @lsp.result = {
      uri: 'file:///tmp/x.rb',
      range: { start: { line: 1, character: 0 }, end: { line: 1, character: 1 } },
    }
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
    assert @editor.lsp_jump_to_definition
    assert_equal 1, @editor.line_index
    assert_equal 0, @editor.byte_pointer
    assert_equal [[0, 2]], @editor.jump_list # previous position pushed
  end

  def test_handles_array_result
    @lsp.result = [
      { uri: 'file:///tmp/x.rb',
        range: { start: { line: 1, character: 3 }, end: { line: 1, character: 4 } } },
    ]
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    assert @editor.lsp_jump_to_definition
    assert_equal 1, @editor.line_index
    assert_equal 3, @editor.byte_pointer
  end

  def test_handles_location_link
    @lsp.result = [
      { targetUri: 'file:///tmp/x.rb',
        targetRange: { start: { line: 0, character: 4 }, end: { line: 0, character: 5 } } },
    ]
    assert @editor.lsp_jump_to_definition
    assert_equal 0, @editor.line_index
    assert_equal 4, @editor.byte_pointer
  end
end
