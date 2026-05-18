# frozen_string_literal: true

require_relative 'test_helper'

# When the user types one of the server-advertised trigger
# characters (`.`, `:`, `@`, …) in insert mode, the completion
# popup auto-fires. No auto-insert of the first candidate so a
# freshly-typed `.` isn't immediately replaced by some method name.

class TestLspManagerTriggerCharacters < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :capabilities
    def initialize(caps); @status = :running; @capabilities = caps; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @manager = Rvim::Lsp::Manager.new(@editor)
    @manager.define_singleton_method(:filetype_for) { |_| :ruby }
  end

  def buf
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['x'] }
  end

  def test_returns_server_advertised_trigger_chars
    @manager.instance_variable_set(:@clients,
      ruby: FakeClient.new(completionProvider: { triggerCharacters: %w[. : @] }))
    assert_equal %w[. : @], @manager.completion_trigger_characters(buf)
  end

  def test_returns_empty_when_no_completion_provider
    @manager.instance_variable_set(:@clients, ruby: FakeClient.new({}))
    assert_equal [], @manager.completion_trigger_characters(buf)
  end

  def test_returns_empty_when_no_client
    @manager.instance_variable_set(:@clients, {})
    assert_equal [], @manager.completion_trigger_characters(buf)
  end
end

class TestEditorCompletionAutoTrigger < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :trigger_chars, :completion_result

    def initialize
      @trigger_chars = %w[. : @]
      @completion_result = nil
    end

    def completion_trigger_characters(_buf); @trigger_chars; end
    def request_completion(_buf); true; end
    def last_completion_result; @completion_result; end
    def flush_changes(_buf); false; end

    def did_open(_); end
    def did_close(_); end
    def note_change(_); false; end
    def maybe_pull_diagnostics(_); false; end
    def maybe_pull_inlay_hints(_); false; end
    def maybe_pull_document_highlight(_); false; end
    def maybe_pull_semantic_tokens(_); false; end
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

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = ['foo.']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 4) # right after `.`
  end

  def fire(ch, mode: :vi_insert)
    @editor.define_singleton_method(:editing_mode_label) { mode }
    @editor.send(:maybe_auto_complete_on_trigger, Reline::Key.new(ch, ch, false))
  end

  def test_dot_in_insert_pops_completion
    @lsp.completion_result = [{ label: 'bar' }, { label: 'baz' }]
    fire('.'.ord)
    assert @editor.instance_variable_get(:@completion_active)
    refute_nil @editor.completion_popup
  end

  def test_non_trigger_char_does_not_fire
    @lsp.completion_result = [{ label: 'bar' }]
    fire('x'.ord)
    refute @editor.instance_variable_get(:@completion_active)
  end

  def test_command_mode_does_not_fire
    fire('.'.ord, mode: :vi_command)
    refute @editor.instance_variable_get(:@completion_active)
  end

  def test_does_not_re_fire_when_completion_already_active
    @editor.instance_variable_set(:@completion_active, true)
    @lsp.completion_result = [{ label: 'bar' }]
    fire('.'.ord)
    # Already active so we don't disturb the open popup. Status
    # message should NOT change to "match 1 of 1".
    refute_match(/match 1/, @editor.status_message.to_s)
  end

  def test_lsp_disabled_does_not_fire
    @editor.settings.set(:lsp_enabled, false)
    fire('.'.ord)
    refute @editor.instance_variable_get(:@completion_active)
  end

  def test_auto_trigger_does_not_replace_typed_dot
    # The buffer's text was already `foo.`; auto-trigger fires
    # with auto_insert: false so the `.` stays as-is.
    @lsp.completion_result = [{ label: 'bar' }, { label: 'baz' }]
    fire('.'.ord)
    assert_equal ['foo.'], @editor.buffer_of_lines, 'no surprise insert'
  end

  def test_no_candidates_skips_pattern_not_found_message
    # On manual <C-N>, an empty result sets "Pattern not found".
    # On auto-trigger, no message — typing chars shouldn't flash
    # error text in the status bar.
    @lsp.completion_result = []
    @editor.buffer_of_lines[0] = '.' # no keyword candidates either
    @editor.instance_variable_set(:@byte_pointer, 1)
    fire('.'.ord)
    refute_match(/Pattern not found/, @editor.status_message.to_s)
  end
end
