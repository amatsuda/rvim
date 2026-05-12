# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

class TestLspHoverClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_handle_response_stores_hover_result
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/hover', 'file:///x']
    msg = { id: 1, result: { contents: { kind: 'markdown', value: '# Title' } } }
    client.send(:handle_response, msg)
    assert_equal 'markdown', client.last_hover_result.dig(:contents, :kind)
  end

  def test_hover_clears_previous_result
    client = make_client
    client.define_singleton_method(:send_message) { |_| nil }
    client.last_hover_result = { contents: 'old' }
    client.hover('file:///x', 0, 0)
    assert_nil client.last_hover_result
  end
end

class TestLspHoverManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_hover_result, :hover_calls

    def initialize
      @status = :running
      @hover_calls = []
      @last_hover_result = nil
    end

    def hover(uri, line, character)
      @hover_calls << { uri: uri, line: line, character: character }
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

  def test_request_hover_sends_cursor_position
    @editor.instance_variable_set(:@line_index, 3)
    @editor.instance_variable_set(:@byte_pointer, 5)
    assert @manager.request_hover(make_buffer)
    call = @client.hover_calls.first
    assert_equal 3, call[:line]
    assert_equal 5, call[:character]
  end

  def test_request_hover_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_hover(make_buffer)
  end

  def test_last_hover_result_reads_from_client
    @client.last_hover_result = { contents: { value: 'hello' } }
    assert_equal 'hello', @manager.last_hover_result.dig(:contents, :value)
  end
end

class TestEditorParseHoverContents < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def parse(result)
    @editor.send(:parse_hover_contents, result)
  end

  def test_nil_result
    assert_equal [], parse(nil)
  end

  def test_markup_content
    out = parse({ contents: { kind: 'markdown', value: "# Title\nbody line" } })
    assert_equal ['# Title', 'body line'], out
  end

  def test_legacy_marked_string_object
    out = parse({ contents: { language: 'ruby', value: "def foo\n  1\nend" } })
    assert_equal ['def foo', '  1', 'end'], out
  end

  def test_legacy_marked_string_plain
    out = parse({ contents: 'just a string' })
    assert_equal ['just a string'], out
  end

  def test_marked_string_array
    out = parse({ contents: ['plain', { language: 'ruby', value: "def foo\nend" }] })
    assert_equal ['plain', 'def foo', 'end'], out
  end

  def test_empty_value_returns_empty
    # An empty value string is "no hover info" — caller surfaces a status
    # message instead of opening an empty popup.
    assert_equal [], parse({ contents: { kind: 'plaintext', value: '' } })
  end

  def test_no_contents_field
    assert_equal [], parse({})
  end
end

class TestEditorLspShowHover < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_hover_returns, :result

    def initialize
      @request_hover_returns = true
      @result = nil
    end

    def request_hover(_buffer)
      @request_hover_returns
    end

    def last_hover_result
      @result
    end

    def flush_changes(_buf); false; end
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
    @buf.lines = ['x = 1']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_show_hover
    assert_nil @editor.hover_popup
  end

  def test_returns_false_when_no_client
    @lsp.request_hover_returns = false
    refute @editor.lsp_show_hover
    assert_nil @editor.hover_popup
  end

  def test_returns_true_with_status_when_no_info
    @lsp.result = { contents: nil }
    assert @editor.lsp_show_hover
    assert_match(/no hover info/, @editor.status_message.to_s)
    assert_nil @editor.hover_popup
  end

  def test_builds_popup_when_result_has_content
    @lsp.result = { contents: { kind: 'markdown', value: "# foo\nbar" } }
    assert @editor.lsp_show_hover
    refute_nil @editor.hover_popup
    assert_equal ['# foo', 'bar'], @editor.hover_popup.contents
  end

  def test_update_dismisses_existing_popup
    @editor.config.editing_mode = :vi_command
    @editor.instance_variable_set(:@hover_popup,
      Rvim::CompletionPopup.new(contents: ['x']))
    refute_nil @editor.hover_popup
    sym = @editor.send(:synthesize_key, 'j').method_symbol
    @editor.update(Reline::Key.new('j', sym, false))
    assert_nil @editor.hover_popup
  end
end
