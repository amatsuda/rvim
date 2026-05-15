# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# textDocument/signatureHelp covers four layers:
#   - Client request shape + handle_response stashing
#   - Manager wiring (cursor-position bound; pump/poll same as hover)
#   - Editor parse_signature_help + format_signature_label
#   - Editor#update auto-trigger on `(` / `,` and dismiss on `)` /
#     mode-change

class TestLspSignatureHelpClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_signature_help_clears_previous_and_sends_position
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_signature_help_result = { signatures: [{}] }
    client.signature_help('file:///x.rb', 3, 7)
    assert_nil client.last_signature_help_result
    assert_equal 'textDocument/signatureHelp', sent[:method]
    assert_equal({ uri: 'file:///x.rb' }, sent[:params][:textDocument])
    assert_equal({ line: 3, character: 7 }, sent[:params][:position])
  end

  def test_handle_response_stashes_signature_help_result
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/signatureHelp', 'file:///x']
    msg = { id: 1, result: { signatures: [{ label: 'foo(a)' }], activeSignature: 0, activeParameter: 0 } }
    client.send(:handle_response, msg)
    assert_equal 'foo(a)', client.last_signature_help_result[:signatures].first[:label]
  end
end

class TestLspSignatureHelpManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_signature_help_result, :calls

    def initialize
      @status = :running
      @calls = []
      @last_signature_help_result = nil
    end

    def signature_help(uri, line, char)
      @calls << { uri: uri, line: line, char: char }
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

  def test_request_signature_help_sends_cursor_position
    @editor.instance_variable_set(:@line_index, 2)
    @editor.instance_variable_set(:@byte_pointer, 5)
    assert @manager.request_signature_help(make_buffer)
    assert_equal({ uri: 'file:///x.rb', line: 2, char: 5 }, @client.calls.first)
  end

  def test_request_signature_help_respects_explicit_position_kwargs
    @editor.instance_variable_set(:@line_index, 9)
    @editor.instance_variable_set(:@byte_pointer, 9)
    assert @manager.request_signature_help(make_buffer, line: 2, character: 4)
    assert_equal({ uri: 'file:///x.rb', line: 2, char: 4 }, @client.calls.first)
  end

  def test_request_signature_help_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_signature_help(make_buffer)
  end

  def test_last_and_clear_signature_help_result
    @client.last_signature_help_result = { signatures: [{ label: 'X' }] }
    assert_equal 'X', @manager.last_signature_help_result[:signatures].first[:label]
    @manager.clear_signature_help_result
    assert_nil @client.last_signature_help_result
  end
end

class TestEditorLspShowSignatureHelp < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result, :flushed, :flush_returns

    def initialize
      @request_returns = true
      @result = nil
      @flushed = false
      @flush_returns = false # default: nothing pending; no settle needed
    end

    def flush_changes(_buf); @flushed = true; @flush_returns; end
    def request_signature_help(_buf, line: nil, character: nil); @request_returns; end
    def last_signature_help_result; @result; end

    def did_open(_buf); end
    def did_close(_buf); end
    def note_change(_buf); false; end
    def maybe_pull_diagnostics(_buf); false; end
    def maybe_pull_inlay_hints(_buf); false; end
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
    @buf.lines = ['"hello".gsub("h", "H")']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
  end

  # ----- parse_signature_help -----

  def test_parse_returns_empty_when_result_nil
    assert_equal [], @editor.send(:parse_signature_help, nil)
  end

  def test_parse_returns_empty_when_no_signatures
    assert_equal [], @editor.send(:parse_signature_help, { signatures: [] })
  end

  def test_parse_marks_active_signature_with_arrow_prefix
    result = {
      signatures: [
        { label: 'foo(a, b)' },
        { label: 'foo(a)' },
      ],
      activeSignature: 1,
      activeParameter: 0,
    }
    out = @editor.send(:parse_signature_help, result)
    assert_equal 2, out.size
    assert out[0].start_with?('  '), "non-active prefix #{out[0].inspect}"
    assert out[1].start_with?('> '), "active prefix #{out[1].inspect}"
  end

  def test_parse_clamps_invalid_active_signature
    result = { signatures: [{ label: 'foo(a)' }], activeSignature: 99, activeParameter: 0 }
    out = @editor.send(:parse_signature_help, result)
    assert out[0].start_with?('> ')
  end

  def test_parse_highlights_active_param_via_string_label
    result = {
      signatures: [{
        label: 'gsub(pattern, replacement)',
        parameters: [{ label: 'pattern' }, { label: 'replacement' }],
      }],
      activeSignature: 0, activeParameter: 1,
    }
    out = @editor.send(:parse_signature_help, result)
    assert_equal '> gsub(pattern, «replacement»)', out[0]
  end

  def test_parse_highlights_active_param_via_label_offset_pair
    # LSP allows ParameterInformation.label to be [start, end] offsets
    # into the parent signature's label. Active param is parameters[1].
    result = {
      signatures: [{
        label: 'foo(a: Int, b: String)',
        parameters: [{ label: [4, 10] }, { label: [12, 21] }],
      }],
      activeSignature: 0, activeParameter: 1,
    }
    out = @editor.send(:parse_signature_help, result)
    assert_equal '> foo(a: Int, «b: String»)', out[0]
  end

  def test_parse_keeps_label_intact_when_active_param_out_of_range
    result = {
      signatures: [{
        label: 'foo(a)', parameters: [{ label: 'a' }],
      }],
      activeSignature: 0, activeParameter: 7,
    }
    out = @editor.send(:parse_signature_help, result)
    assert_equal '> foo(a)', out[0]
  end

  # ----- lsp_show_signature_help -----

  def test_show_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_show_signature_help
  end

  def test_show_returns_true_and_sets_no_info_status_when_empty
    @lsp.result = { signatures: [] }
    assert @editor.lsp_show_signature_help
    assert_match(/no signature info/, @editor.status_message.to_s)
    assert_nil @editor.signature_popup
  end

  def test_show_populates_signature_popup_with_active_marker
    @lsp.result = {
      signatures: [{ label: 'foo(a)', parameters: [{ label: 'a' }] }],
      activeSignature: 0, activeParameter: 0,
    }
    assert @editor.lsp_show_signature_help
    refute_nil @editor.signature_popup
    assert_equal ['> foo(«a»)'], @editor.signature_popup.contents
  end

  def test_show_flushes_pending_changes_first
    @lsp.result = { signatures: [{ label: 'x()' }] }
    @editor.lsp_show_signature_help
    assert @lsp.flushed, 'expected flush_changes to be called before signatureHelp'
  end

  def test_show_settles_briefly_when_didchange_was_flushed
    # ruby-lsp races between its reader-thread parse and its worker-
    # thread didChange application. When flush_changes actually sent a
    # didChange we sleep briefly so the worker can apply it before our
    # signatureHelp request lands.
    @lsp.flush_returns = true
    @lsp.result = { signatures: [{ label: 'x()' }] }
    t0 = Time.now
    @editor.lsp_show_signature_help
    elapsed = Time.now - t0
    settle = Rvim::Editor::SIGNATURE_HELP_DIDCHANGE_SETTLE
    assert elapsed >= settle, "expected at least #{settle}s of settle, got #{elapsed}"
  end

  def test_show_does_not_settle_when_nothing_was_flushed
    @lsp.flush_returns = false
    @lsp.result = { signatures: [{ label: 'x()' }] }
    t0 = Time.now
    @editor.lsp_show_signature_help
    elapsed = Time.now - t0
    settle = Rvim::Editor::SIGNATURE_HELP_DIDCHANGE_SETTLE
    assert elapsed < settle, "expected no settle delay, got #{elapsed}"
  end
end

class TestEditorSignatureHelpAutoTrigger < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :result, :request_count, :last_position

    def initialize
      @result = { signatures: [{ label: 'foo()' }], activeSignature: 0, activeParameter: 0 }
      @request_count = 0
      @last_position = nil
    end

    def flush_changes(_buf); end

    def request_signature_help(_buf, line: nil, character: nil)
      @request_count += 1
      @last_position = { line: line, character: character }
      true
    end
    def last_signature_help_result; @result; end

    def did_open(_buf); end
    def did_close(_buf); end
    def note_change(_buf); false; end
    def maybe_pull_diagnostics(_buf); false; end
    def maybe_pull_inlay_hints(_buf); false; end
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
    @buf.lines = ['']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
  end

  def fire(ch, mode: :vi_insert)
    @editor.define_singleton_method(:editing_mode_label) { mode }
    key = Reline::Key.new(ch, nil, false)
    @editor.send(:update_signature_popup, key, :vi_insert)
  end

  def test_open_paren_triggers_signature_help
    fire('(')
    assert_equal 1, @lsp.request_count
    refute_nil @editor.signature_popup
  end

  def test_comma_triggers_signature_help
    fire(',')
    assert_equal 1, @lsp.request_count
  end

  def test_letter_does_not_trigger
    fire('a')
    assert_equal 0, @lsp.request_count
  end

  def test_close_paren_dismisses_existing_popup
    fire('(')
    refute_nil @editor.signature_popup
    fire(')')
    assert_nil @editor.signature_popup
  end

  def test_mode_change_dismisses_existing_popup
    fire('(')
    refute_nil @editor.signature_popup
    fire('x', mode: :vi_command)
    assert_nil @editor.signature_popup
  end

  def test_does_not_trigger_in_command_mode
    fire('(', mode: :vi_command)
    assert_equal 0, @lsp.request_count
  end

  def test_auto_trigger_backs_position_off_by_one
    # After `'hello'.gsub(` the cursor is at column 13. ruby-lsp's
    # CallNode end_offset is exclusive, so position 13 lands outside;
    # we send position 12 (AT the `(`) to land inside the node.
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 13)
    fire('(')
    assert_equal({ line: 0, character: 12 }, @lsp.last_position)
  end

  def test_auto_trigger_clamps_position_at_zero
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    fire('(')
    assert_equal 0, @lsp.last_position[:character]
  end
end
