# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# textDocument/selectionRange covers three layers:
#   - Client request shape + handle_response stashing
#   - Manager wiring + capability gate
#   - Editor expand/shrink with cached hierarchy

class TestLspSelectionRangeClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_selection_range_clears_and_sends_positions_array
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_selection_range_result = [{}]
    client.selection_range('file:///x.rb', 2, 13)
    assert_nil client.last_selection_range_result
    assert_equal 'textDocument/selectionRange', sent[:method]
    assert_equal [{ line: 2, character: 13 }], sent[:params][:positions]
  end

  def test_handle_response_stashes_array_of_selection_ranges
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/selectionRange', 'file:///x']
    msg = { id: 1, result: [
      { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } },
        parent: { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 5 } } } },
    ] }
    client.send(:handle_response, msg)
    assert_equal 1, client.last_selection_range_result.size
  end
end

class TestLspSelectionRangeManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :capabilities, :last_selection_range_result, :calls

    def initialize
      @status = :running
      @capabilities = { selectionRangeProvider: true }
      @calls = []
    end

    def selection_range(uri, line, char); @calls << { uri: uri, line: line, char: char }; end
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
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['name.upcase'] }
  end

  def test_request_calls_client_with_cursor
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 4)
    assert @manager.request_selection_range(make_buffer)
    assert_equal({ uri: 'file:///x.rb', line: 0, char: 4 }, @client.calls.first)
  end

  def test_request_returns_unsupported_without_capability
    @client.capabilities = {}
    assert_equal :unsupported, @manager.request_selection_range(make_buffer)
    assert_empty @client.calls
  end
end

class TestEditorLspSelectionRange < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result

    def initialize
      @request_returns = true
      @result = nil
    end

    def flush_changes(_buf); false; end
    def request_selection_range(_buf); @request_returns; end
    def last_selection_range_result; @result; end

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
    @buf.lines = ['class Greeter', '  def hello(name)', '    "hi, " + name.upcase', '  end', 'end']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 2)
    @editor.instance_variable_set(:@byte_pointer, 13)
  end

  # ----- expand -----

  def test_expand_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_selection_expand
  end

  def test_expand_surfaces_unsupported_status
    @lsp.request_returns = :unsupported
    assert @editor.lsp_selection_expand
    assert_match(/does not support selectionRange/, @editor.status_message.to_s)
  end

  def test_expand_status_when_server_returns_empty
    @lsp.result = []
    assert @editor.lsp_selection_expand
    assert_match(/no selection range/, @editor.status_message.to_s)
  end

  def test_expand_sets_visual_selection_to_innermost
    @lsp.result = [{
      range: { start: { line: 2, character: 13 }, end: { line: 2, character: 17 } },
    }]
    assert @editor.lsp_selection_expand
    assert_equal :char, @editor.visual_mode
    assert_equal [2, 13], @editor.visual_anchor
    assert_equal 2, @editor.line_index
    assert_equal 16, @editor.byte_pointer # end_char 17 - 1 (inclusive)
  end

  def test_repeated_expand_advances_through_hierarchy
    @lsp.result = [{
      range: { start: { line: 2, character: 13 }, end: { line: 2, character: 17 } },
      parent: {
        range: { start: { line: 2, character: 13 }, end: { line: 2, character: 24 } },
        parent: {
          range: { start: { line: 2, character: 4 }, end: { line: 2, character: 24 } },
        },
      },
    }]
    @editor.lsp_selection_expand
    assert_equal 13, @editor.visual_anchor[1]
    assert_equal 16, @editor.byte_pointer

    @editor.lsp_selection_expand # → level 1, "name.upcase"
    assert_equal 13, @editor.visual_anchor[1]
    assert_equal 23, @editor.byte_pointer

    @editor.lsp_selection_expand # → level 2, '"hi, " + name.upcase'
    assert_equal 4, @editor.visual_anchor[1]
    assert_equal 23, @editor.byte_pointer
  end

  def test_expand_dedupes_consecutive_identical_ranges
    @lsp.result = [{
      range: { start: { line: 2, character: 13 }, end: { line: 2, character: 17 } },
      parent: {
        range: { start: { line: 2, character: 13 }, end: { line: 2, character: 17 } }, # duplicate
        parent: {
          range: { start: { line: 2, character: 4 }, end: { line: 2, character: 24 } },
        },
      },
    }]
    @editor.lsp_selection_expand
    @editor.lsp_selection_expand
    # After two expands we should have skipped the duplicate and be at the outermost (line 2 char 4-24).
    assert_equal 4, @editor.visual_anchor[1]
    assert_equal 23, @editor.byte_pointer
  end

  def test_expand_past_outermost_shows_status
    @lsp.result = [{
      range: { start: { line: 2, character: 13 }, end: { line: 2, character: 17 } },
    }]
    @editor.lsp_selection_expand # level 0
    @editor.lsp_selection_expand # tries level 1, but only one level
    assert_match(/at outermost/, @editor.status_message.to_s)
  end

  # ----- shrink -----

  def test_shrink_past_innermost_shows_status
    @lsp.result = [{
      range: { start: { line: 2, character: 13 }, end: { line: 2, character: 17 } },
    }]
    @editor.lsp_selection_expand # level 0
    @editor.lsp_selection_shrink
    assert_match(/at innermost/, @editor.status_message.to_s)
  end

  def test_shrink_walks_back_through_hierarchy
    @lsp.result = [{
      range: { start: { line: 2, character: 13 }, end: { line: 2, character: 17 } },
      parent: {
        range: { start: { line: 2, character: 13 }, end: { line: 2, character: 24 } },
      },
    }]
    @editor.lsp_selection_expand # level 0 (name)
    @editor.lsp_selection_expand # level 1 (name.upcase)
    assert_equal 23, @editor.byte_pointer
    @editor.lsp_selection_shrink # back to level 0
    assert_equal 16, @editor.byte_pointer
  end

  # ----- cache invalidation -----

  def test_expand_refetches_when_cursor_moved_away
    @lsp.result = [{
      range: { start: { line: 2, character: 13 }, end: { line: 2, character: 17 } },
      parent: { range: { start: { line: 2, character: 13 }, end: { line: 2, character: 24 } } },
    }]
    @editor.lsp_selection_expand # level 0
    # User moves cursor (e.g., by pressing Esc + h)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.instance_variable_set(:@visual_anchor, nil)
    @editor.instance_variable_set(:@visual_mode, nil)
    # Fresh request happens; we'll feed a different result this time.
    @lsp.result = [{
      range: { start: { line: 0, character: 6 }, end: { line: 0, character: 13 } },
    }]
    @editor.lsp_selection_expand
    assert_equal [0, 6], @editor.visual_anchor
    assert_equal 12, @editor.byte_pointer
  end
end
