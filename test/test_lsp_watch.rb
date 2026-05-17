# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# Server window/{log,show}Message notifications are captured into a
# bounded ring on the client. :LspWatch opens a terminal-style buffer
# that streams new entries as they arrive, via pump_lsp_watch_buffers.

class TestLspClientWindowMessages < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_log_message_dispatched_to_window_messages
    client = make_client
    client.send(:dispatch, { method: 'window/logMessage', params: { type: 3, message: 'hello' } })
    assert_equal 1, client.window_messages.size
    entry = client.window_messages.first
    assert_equal 'logMessage', entry[:kind]
    assert_equal 3, entry[:type]
    assert_equal 'hello', entry[:message]
    assert entry[:time].is_a?(Time)
  end

  def test_show_message_routed_to_same_ring_tagged_as_showMessage
    client = make_client
    client.send(:dispatch, { method: 'window/showMessage', params: { type: 1, message: 'boom' } })
    assert_equal 'showMessage', client.window_messages.first[:kind]
    assert_equal 1, client.window_messages.first[:type]
  end

  def test_ring_caps_at_limit
    client = make_client
    cap = Rvim::Lsp::Client::WINDOW_MESSAGE_LIMIT
    (cap + 5).times do |i|
      client.send(:record_window_message, kind: 'logMessage', type: 4, message: "m#{i}")
    end
    assert_equal cap, client.window_messages.size
    # Oldest dropped: first kept message starts at offset 5.
    assert_equal 'm5', client.window_messages.first[:message]
  end
end

class TestLspManagerWindowMessages < Test::Unit::TestCase
  class FakeClient
    attr_reader :name, :window_messages
    def initialize(name, messages); @name = name; @window_messages = messages; end
    def status; :running; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @manager = Rvim::Lsp::Manager.new(@editor)
  end

  def test_aggregates_and_sorts_by_time_and_tags_source
    t0 = Time.at(1000)
    t1 = Time.at(2000)
    t2 = Time.at(3000)
    a = FakeClient.new('rubylsp', [{ time: t0, kind: 'logMessage', type: 4, message: 'A' },
                                    { time: t2, kind: 'logMessage', type: 4, message: 'C' }])
    b = FakeClient.new('other',   [{ time: t1, kind: 'showMessage', type: 1, message: 'B' }])
    @manager.instance_variable_set(:@clients, { ruby: a, py: b })

    out = @manager.window_messages
    assert_equal %w[A B C], out.map { |m| m[:message] }
    assert_equal %w[rubylsp other rubylsp], out.map { |m| m[:source] }
  end
end

class TestEditorLspWatch < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :messages

    def initialize; @messages = []; end
    def window_messages; @messages; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)
  end

  def test_open_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_open_watch_buffer
  end

  def test_open_creates_buffer_with_current_messages
    @lsp.messages = [
      { time: Time.at(0), kind: 'logMessage',  type: 3, message: 'startup',  source: 'rubylsp' },
      { time: Time.at(1), kind: 'showMessage', type: 2, message: 'careful',  source: 'rubylsp' },
    ]
    assert @editor.lsp_open_watch_buffer
    refute_nil @editor.current_buffer
    lines = @editor.current_buffer.lines
    assert_match(/LSP server log/, lines[0])
    assert(lines.any? { |l| l =~ /\[I\]\s+\(rubylsp\) startup/ })
    assert(lines.any? { |l| l =~ /\[W\]\*\s+\(rubylsp\) careful/ })
  end

  def test_pump_appends_new_messages_as_they_arrive
    @lsp.messages = [{ time: Time.at(0), kind: 'logMessage', type: 4, message: 'one', source: 's' }]
    @editor.lsp_open_watch_buffer
    pre = @editor.current_buffer.lines.size

    @lsp.messages << { time: Time.at(1), kind: 'logMessage', type: 4, message: 'two', source: 's' }
    @lsp.messages << { time: Time.at(2), kind: 'logMessage', type: 4, message: 'three', source: 's' }
    @editor.pump_lsp_watch_buffers

    post = @editor.current_buffer.lines.size
    assert_equal pre + 2, post
    assert_match(/two/, @editor.current_buffer.lines[-2])
    assert_match(/three/, @editor.current_buffer.lines[-1])
  end

  def test_pump_keeps_buffer_of_lines_in_sync_with_current_buffer
    @lsp.messages = []
    @editor.lsp_open_watch_buffer
    @lsp.messages << { time: Time.at(0), kind: 'logMessage', type: 4, message: 'x', source: 's' }
    @editor.pump_lsp_watch_buffers
    assert_equal @editor.current_buffer.lines, @editor.buffer_of_lines
  end

  def test_pump_drops_entries_whose_buffer_was_closed
    @lsp.messages = []
    @editor.lsp_open_watch_buffer
    closed = @editor.current_buffer
    @editor.instance_variable_get(:@buffers).delete(closed.id)
    @lsp.messages << { time: Time.at(0), kind: 'logMessage', type: 4, message: 'x', source: 's' }
    @editor.pump_lsp_watch_buffers
    assert_empty @editor.instance_variable_get(:@lsp_watch_buffers)
  end
end
