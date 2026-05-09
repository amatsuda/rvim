# frozen_string_literal: true

require_relative 'test_helper'

# Manager#note_change is called once per render tick. It should send
# textDocument/didChange exactly when the buffer's line array fingerprint
# differs from the last synced one, modulo a leading-edge debounce window.
class TestLspNoteChange < Test::Unit::TestCase
  class FakeClient
    attr_reader :did_open_calls, :did_change_calls, :did_close_calls
    attr_accessor :status

    def initialize
      @status = :running
      @did_open_calls = []
      @did_change_calls = []
      @did_close_calls = []
    end

    def did_open(uri, _lang, version, text)
      @did_open_calls << { uri: uri, version: version, text: text }
    end

    def did_change(uri, version, text, range: nil)
      @did_change_calls << { uri: uri, version: version, text: text, range: range }
    end

    def did_close(uri)
      @did_close_calls << uri
    end

    def diagnostics
      {}
    end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @manager = Rvim::Lsp::Manager.new(@editor)
    @manager.instance_variable_set(:@test_clock, 1000.0)
    @manager.define_singleton_method(:monotonic_now) { @test_clock }
    @manager.define_singleton_method(:filetype_for) { |_| :ruby }
    @manager.define_singleton_method(:buffer_uri) { |_| 'file:///x.rb' }
    @client = FakeClient.new
    @manager.instance_variable_set(:@clients, { ruby: @client })
  end

  def make_buffer(lines)
    buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    buf.lines = lines
    buf
  end

  def advance(dt)
    cur = @manager.instance_variable_get(:@test_clock)
    @manager.instance_variable_set(:@test_clock, cur + dt)
  end

  def test_note_change_no_op_after_did_open_with_unchanged_buffer
    buf = make_buffer(['x = 1'])
    @manager.did_open(buf)
    advance(1.0) # past debounce window so that's not what blocks us
    refute @manager.note_change(buf)
    assert_empty @client.did_change_calls
  end

  def test_note_change_fires_on_buffer_change
    buf = make_buffer(['x = 1'])
    @manager.did_open(buf)
    advance(1.0)
    buf.lines = ['x = 2']
    assert @manager.note_change(buf)
    assert_equal 1, @client.did_change_calls.size
    assert_equal 'file:///x.rb', @client.did_change_calls.first[:uri]
    assert_equal "x = 2", @client.did_change_calls.first[:text]
  end

  def test_note_change_debounces_within_window
    buf = make_buffer(['x = 1'])
    @manager.did_open(buf)
    advance(1.0)
    buf.lines = ['x = 2']
    @manager.note_change(buf)
    advance(0.05) # well within CHANGE_DEBOUNCE_INTERVAL (0.15)
    buf.lines = ['x = 3']
    refute @manager.note_change(buf)
    assert_equal 1, @client.did_change_calls.size
  end

  def test_note_change_fires_again_after_debounce_window
    buf = make_buffer(['x = 1'])
    @manager.did_open(buf)
    advance(1.0)
    buf.lines = ['x = 2']
    @manager.note_change(buf)
    advance(0.20) # past CHANGE_DEBOUNCE_INTERVAL
    buf.lines = ['x = 3']
    assert @manager.note_change(buf)
    assert_equal 2, @client.did_change_calls.size
    assert_equal 'x = 3', @client.did_change_calls.last[:text]
  end

  def test_note_change_no_op_without_client_for_filetype
    buf = make_buffer(['x = 1'])
    @manager.instance_variable_set(:@clients, {})
    refute @manager.note_change(buf)
    assert_empty @client.did_change_calls
  end

  def test_note_change_no_op_when_client_not_running
    buf = make_buffer(['x = 1'])
    @client.status = :starting
    @manager.did_open(buf)
    advance(1.0)
    buf.lines = ['x = 2']
    refute @manager.note_change(buf)
    assert_empty @client.did_change_calls
  end

  def test_note_change_no_op_when_buffer_nil
    refute @manager.note_change(nil)
    assert_empty @client.did_change_calls
  end

  def test_did_close_clears_synced_state
    buf = make_buffer(['x = 1'])
    @manager.did_open(buf)
    fps = @manager.instance_variable_get(:@synced_fingerprints)
    refute_nil fps[buf.id]
    @manager.did_close(buf)
    refute fps.key?(buf.id)
  end

  def test_did_change_sends_incremental_range_spanning_old_doc
    # ruby-lsp uses TextDocumentSyncKind.Incremental and ignores bare-{text}
    # change events. The range must cover the OLD document so the server
    # knows to replace everything.
    buf = make_buffer(['a = 1'])
    @manager.did_open(buf)
    advance(1.0)
    buf.lines = ['a = 1', 'b = 2']
    @manager.note_change(buf)
    call = @client.did_change_calls.first
    refute_nil call[:range], 'expected an incremental range'
    assert_equal({ line: 0, character: 0 }, call[:range][:start])
    # OLD doc was ['a = 1'] — one line, 5 chars.
    assert_equal({ line: 0, character: 5 }, call[:range][:end])
  end

  def test_did_change_range_advances_across_consecutive_edits
    buf = make_buffer(['a = 1'])
    @manager.did_open(buf)
    advance(1.0)
    buf.lines = ['a = 1', 'b = 2']
    @manager.note_change(buf)
    advance(0.5)
    buf.lines = ['a = 1', 'b = 2', 'c = 3']
    @manager.note_change(buf)
    second_call = @client.did_change_calls[1]
    # OLD doc going into the second edit was ['a = 1', 'b = 2'] — line 1, 5 chars.
    assert_equal({ line: 1, character: 5 }, second_call[:range][:end])
  end

  def test_version_increments_across_did_open_and_did_change
    buf = make_buffer(['x = 1'])
    @manager.did_open(buf)
    open_version = @client.did_open_calls.first[:version]
    advance(1.0)
    buf.lines = ['x = 2']
    @manager.note_change(buf)
    change_version = @client.did_change_calls.first[:version]
    assert change_version > open_version, "expected version to advance after change"
  end
end
