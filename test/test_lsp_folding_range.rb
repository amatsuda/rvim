# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# textDocument/foldingRange covers three layers:
#   - Client request shape + handle_response stashing
#   - Manager wiring + capability gate
#   - Editor lsp_apply_folding_ranges populates Buffer#folds

class TestLspFoldingRangeClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_folding_range_clears_previous_and_sends_uri_only
    client = make_client
    sent = nil
    client.define_singleton_method(:send_message) { |body| sent = body }
    client.last_folding_range_result = [{}]
    client.folding_range('file:///x.rb')
    assert_nil client.last_folding_range_result
    assert_equal 'textDocument/foldingRange', sent[:method]
    assert_equal({ uri: 'file:///x.rb' }, sent[:params][:textDocument])
    refute sent[:params].key?(:position)
  end

  def test_handle_response_stashes_ranges
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/foldingRange', 'file:///x']
    msg = { id: 1, result: [
      { startLine: 0, endLine: 4, kind: 'region' },
      { startLine: 1, endLine: 3 },
    ] }
    client.send(:handle_response, msg)
    assert_equal 2, client.last_folding_range_result.size
  end
end

class TestLspFoldingRangeManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :capabilities, :last_folding_range_result, :calls

    def initialize
      @status = :running
      @capabilities = { foldingRangeProvider: true }
      @last_folding_range_result = nil
      @calls = []
    end

    def folding_range(uri); @calls << uri; end
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

  def test_request_folding_range_calls_client_with_uri
    assert @manager.request_folding_range(make_buffer)
    assert_equal ['file:///x.rb'], @client.calls
  end

  def test_request_folding_range_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_folding_range(make_buffer)
  end

  def test_request_folding_range_returns_unsupported_without_capability
    @client.capabilities = {}
    assert_equal :unsupported, @manager.request_folding_range(make_buffer)
    assert_empty @client.calls
  end
end

class TestEditorLspApplyFoldingRanges < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_returns, :result

    def initialize
      @request_returns = true
      @result = nil
    end

    def flush_changes(_buf); false; end
    def request_folding_range(_buf); @request_returns; end
    def last_folding_range_result; @result; end

    def pending_for?(_); false; end
    def pump; end
    def diagnostic_signs(_); {}; end
    def diagnostic_ranges(_); {}; end
    def diagnostics_for(_); []; end
    def document_highlights_by_line(_); {}; end
    def inlay_hints_by_line(_); {}; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = (1..20).map { |i| "line#{i}" }
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_apply_folding_ranges
  end

  def test_returns_false_when_request_unavailable
    @lsp.request_returns = false
    refute @editor.lsp_apply_folding_ranges
  end

  def test_surfaces_unsupported_as_status_message
    @lsp.request_returns = :unsupported
    assert @editor.lsp_apply_folding_ranges
    assert_match(/does not support foldingRange/, @editor.status_message.to_s)
  end

  def test_no_folds_status_message
    @lsp.result = []
    assert @editor.lsp_apply_folding_ranges
    assert_match(/no folding ranges/, @editor.status_message.to_s)
    assert_predicate @buf.folds, :empty?
  end

  def test_populates_buffer_folds_in_open_state
    @lsp.result = [
      { startLine: 0, endLine: 5, kind: 'region' },
      { startLine: 8, endLine: 12 },
    ]
    assert @editor.lsp_apply_folding_ranges
    assert_match(/applied 2 fold/, @editor.status_message.to_s)
    folds = @buf.folds.each.to_a
    assert_equal 2, folds.size
    refute folds[0].closed
    refute folds[1].closed
  end

  def test_dedupes_identical_ranges
    # ruby-lsp occasionally emits the same range twice; Folds#add
    # rejects exact duplicates as partial-overlap, but we shouldn't
    # waste an add() call on them.
    @lsp.result = [
      { startLine: 0, endLine: 5 },
      { startLine: 0, endLine: 5 },
      { startLine: 8, endLine: 12 },
    ]
    @editor.lsp_apply_folding_ranges
    assert_equal 2, @buf.folds.each.to_a.size
    assert_match(/applied 2 fold/, @editor.status_message.to_s)
  end

  def test_turns_on_foldenable_so_folds_actually_render
    @editor.settings.set(:foldenable, false)
    @lsp.result = [{ startLine: 0, endLine: 5 }]
    @editor.lsp_apply_folding_ranges
    assert_equal true, @editor.settings.get(:foldenable)
  end

  def test_does_not_touch_foldenable_when_nothing_was_added
    @editor.settings.set(:foldenable, false)
    @lsp.result = []
    @editor.lsp_apply_folding_ranges
    assert_equal false, @editor.settings.get(:foldenable)
  end

  def test_creates_nested_folds_when_ranges_properly_contain
    # `class Greeter ... end` contains `def hello ... end`
    @lsp.result = [
      { startLine: 0, endLine: 10 },
      { startLine: 1, endLine: 5 },
    ]
    assert @editor.lsp_apply_folding_ranges
    folds = @buf.folds.each.to_a
    assert_equal 2, folds.size, "nested folds should both be added"
  end

  def test_replaces_existing_folds_on_refresh
    @buf.folds.add(0, 3, closed: true) # user-added manual fold
    @lsp.result = [{ startLine: 5, endLine: 9 }]
    @editor.lsp_apply_folding_ranges
    folds = @buf.folds.each.to_a
    assert_equal 1, folds.size
    assert_equal 5, folds[0].start_line
  end

  def test_skips_zero_length_or_inverted_ranges
    @lsp.result = [
      { startLine: 0, endLine: 0 }, # zero-length: skip
      { startLine: 5, endLine: 3 }, # inverted: skip
      { startLine: 7, endLine: 9 }, # valid
    ]
    @editor.lsp_apply_folding_ranges
    assert_equal 1, @buf.folds.each.to_a.size
  end
end
