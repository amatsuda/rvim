# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# textDocument/typeDefinition and textDocument/implementation use the
# same response shape as textDocument/definition. Tests focus on the
# wiring (each kind reaches its own state slot) and the shared
# jump_to_first_location tail.

class TestLspTypeDefAndImplClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_type_definition_clears_previous_and_sends_position
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_type_definition_result = { uri: 'old' }
    client.type_definition('file:///x.rb', 2, 5)
    assert_nil client.last_type_definition_result
    assert_equal 'textDocument/typeDefinition', sent[:method]
    assert_equal({ line: 2, character: 5 }, sent[:params][:position])
  end

  def test_implementation_clears_previous_and_sends_position
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_implementation_result = { uri: 'old' }
    client.implementation('file:///x.rb', 0, 0)
    assert_nil client.last_implementation_result
    assert_equal 'textDocument/implementation', sent[:method]
  end

  def test_handle_response_routes_to_correct_slot
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/typeDefinition', 'file:///x']
    client.instance_variable_get(:@pending)[2] = ['textDocument/implementation', 'file:///x']
    td = { uri: 'file:///t.rb', range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } } }
    im = { uri: 'file:///i.rb', range: { start: { line: 1, character: 0 }, end: { line: 1, character: 1 } } }
    client.send(:handle_response, { id: 1, result: td })
    client.send(:handle_response, { id: 2, result: im })
    assert_equal 'file:///t.rb', client.last_type_definition_result[:uri]
    assert_equal 'file:///i.rb', client.last_implementation_result[:uri]
  end
end

class TestLspTypeDefAndImplManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :capabilities,
                  :last_type_definition_result, :last_implementation_result,
                  :type_definition_calls, :implementation_calls

    def initialize
      @status = :running
      @type_definition_calls = []
      @implementation_calls = []
      @last_type_definition_result = nil
      @last_implementation_result = nil
      @capabilities = { typeDefinitionProvider: true, implementationProvider: true }
    end

    def type_definition(uri, line, char)
      @type_definition_calls << { uri: uri, line: line, char: char }
    end

    def implementation(uri, line, char)
      @implementation_calls << { uri: uri, line: line, char: char }
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

  def test_request_type_definition_sends_cursor_position
    @editor.instance_variable_set(:@line_index, 3)
    @editor.instance_variable_set(:@byte_pointer, 7)
    assert @manager.request_type_definition(make_buffer)
    assert_equal({ uri: 'file:///x.rb', line: 3, char: 7 }, @client.type_definition_calls.first)
  end

  def test_request_implementation_sends_cursor_position
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 4)
    assert @manager.request_implementation(make_buffer)
    assert_equal({ uri: 'file:///x.rb', line: 1, char: 4 }, @client.implementation_calls.first)
  end

  def test_requests_return_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_type_definition(make_buffer)
    refute @manager.request_implementation(make_buffer)
  end

  def test_request_type_definition_returns_unsupported_when_server_lacks_capability
    @client.capabilities = { implementationProvider: true } # no typeDefinitionProvider
    assert_equal :unsupported, @manager.request_type_definition(make_buffer)
    assert_empty @client.type_definition_calls
  end

  def test_request_implementation_returns_unsupported_when_server_lacks_capability
    @client.capabilities = { typeDefinitionProvider: true } # no implementationProvider
    assert_equal :unsupported, @manager.request_implementation(make_buffer)
    assert_empty @client.implementation_calls
  end

  def test_supports_via_options_object_not_just_true
    # Per LSP, the provider value can be a registration options object.
    @client.capabilities = { typeDefinitionProvider: { id: 'foo' } }
    assert_equal true, @manager.request_type_definition(make_buffer)
  end

  def test_explicit_false_is_unsupported
    @client.capabilities = { typeDefinitionProvider: false }
    assert_equal :unsupported, @manager.request_type_definition(make_buffer)
  end
end

class TestEditorLspJumpToTypeDefAndImpl < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :td_returns, :im_returns, :td_result, :im_result

    def initialize
      @td_returns = true
      @im_returns = true
      @td_result = nil
      @im_result = nil
    end

    def flush_changes(_buf); false; end
    def request_type_definition(_buf); @td_returns; end
    def request_implementation(_buf); @im_returns; end
    def maybe_pull_inlay_hints(_buf); false; end
    def last_type_definition_result; @td_result; end
    def last_implementation_result; @im_result; end

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
    @buf.lines = ['x = 1', 'y = 2']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.instance_variable_set(:@filepath, '/tmp/x.rb')
  end

  # ----- typeDefinition -----

  def test_type_def_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_jump_to_type_definition
  end

  def test_type_def_returns_false_when_request_fails
    @lsp.td_returns = false
    refute @editor.lsp_jump_to_type_definition
  end

  def test_type_def_status_message_when_no_result
    @lsp.td_result = []
    assert @editor.lsp_jump_to_type_definition
    assert_match(/no type definition/, @editor.status_message.to_s)
  end

  def test_type_def_jumps_to_target_in_same_file
    @lsp.td_result = {
      uri: 'file:///tmp/x.rb',
      range: { start: { line: 1, character: 2 }, end: { line: 1, character: 3 } },
    }
    @editor.instance_variable_set(:@byte_pointer, 4)
    assert @editor.lsp_jump_to_type_definition
    assert_equal 1, @editor.line_index
    assert_equal 2, @editor.byte_pointer
    assert_equal [[0, 4]], @editor.jump_list
  end

  def test_type_def_handles_location_link
    @lsp.td_result = [
      { targetUri: 'file:///tmp/x.rb',
        targetRange: { start: { line: 0, character: 4 }, end: { line: 0, character: 5 } } },
    ]
    assert @editor.lsp_jump_to_type_definition
    assert_equal 4, @editor.byte_pointer
  end

  # ----- implementation -----

  def test_impl_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_jump_to_implementation
  end

  def test_impl_status_message_when_no_result
    @lsp.im_result = []
    assert @editor.lsp_jump_to_implementation
    assert_match(/no implementation/, @editor.status_message.to_s)
  end

  def test_impl_jumps_to_target
    @lsp.im_result = [
      { uri: 'file:///tmp/x.rb',
        range: { start: { line: 1, character: 0 }, end: { line: 1, character: 1 } } },
    ]
    @editor.instance_variable_set(:@byte_pointer, 3)
    assert @editor.lsp_jump_to_implementation
    assert_equal 1, @editor.line_index
    assert_equal 0, @editor.byte_pointer
  end

  def test_type_def_surfaces_unsupported_as_status_message
    # ruby-lsp 0.26.x advertises neither provider; rather than hanging
    # for the 2s timeout we tell the user up front.
    @lsp.td_returns = :unsupported
    assert @editor.lsp_jump_to_type_definition
    assert_match(/does not support typeDefinition/, @editor.status_message.to_s)
  end

  def test_impl_surfaces_unsupported_as_status_message
    @lsp.im_returns = :unsupported
    assert @editor.lsp_jump_to_implementation
    assert_match(/does not support implementation/, @editor.status_message.to_s)
  end
end
