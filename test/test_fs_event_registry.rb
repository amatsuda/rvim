# frozen_string_literal: true

require_relative 'test_helper'

# Rvim::FsEventRegistry: tracks live FsWatcher handles, drains
# their event queues each tick, dispatches libuv-shape callbacks
# (err, filename, events) on the main thread.

class TestFsEventRegistry < Test::Unit::TestCase
  class FakeWatcher
    attr_reader :id
    attr_accessor :queued, :stopped

    @@next = 200
    def initialize
      @id = (@@next += 1)
      @queued = []
      @stopped = false
    end

    def start; end
    def stop; @stopped = true; end
    def drain; out = @queued.dup; @queued.clear; out; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @registry = Rvim::FsEventRegistry.new(@editor)
  end

  def test_register_starts_watcher_and_returns_id
    w = FakeWatcher.new
    id = @registry.register(w, ->(_, _, _) {})
    assert_equal w.id, id
    assert_equal w, @registry.get(id)
  end

  def test_drain_all_dispatches_libuv_shape_callback
    calls = []
    w = FakeWatcher.new
    @registry.register(w, ->(err, filename, events) { calls << [err, filename, events] })
    w.queued = [{ filename: 'foo', events: { change: true } }]
    @registry.drain_all
    assert_equal [[nil, 'foo', { change: true }]], calls
  end

  def test_stop_removes_and_halts_watcher
    w = FakeWatcher.new
    @registry.register(w, nil)
    assert @registry.stop(w.id)
    assert w.stopped
    assert_nil @registry.get(w.id)
    refute @registry.stop(w.id), 'second stop is a no-op'
  end

  def test_shutdown_stops_every_watcher
    a = FakeWatcher.new
    b = FakeWatcher.new
    @registry.register(a, nil)
    @registry.register(b, nil)
    @registry.shutdown
    assert a.stopped
    assert b.stopped
    assert_equal 0, @registry.size
  end

  def test_callback_error_does_not_take_registry_down
    w = FakeWatcher.new
    @registry.register(w, ->(_e, _f, _ev) { raise 'boom' })
    w.queued = [{ filename: 'x', events: { change: true } }]
    assert_nothing_raised { @registry.drain_all }
    assert_match(/boom/, @editor.status_message.to_s)
  end
end
