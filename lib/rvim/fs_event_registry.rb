# frozen_string_literal: true

module Rvim
  # Holds live Rvim::FsWatcher handles by id, drains their event
  # queues on each render-loop tick, and dispatches libuv-shape
  # callbacks `cb(err, filename, events)` on the MAIN THREAD.
  #
  # Mirrors Rvim::JobRegistry's structure so the editor wiring is
  # symmetric (pump_fs_events ↔ pump_jobs).
  class FsEventRegistry
    def initialize(editor)
      @editor = editor
      @watchers = {} # id -> { watcher:, callback: }
    end

    # Register a not-yet-started FsWatcher with a libuv-shape
    # callback `cb(err, filename, events)`. Starts the watcher and
    # returns its id.
    def register(watcher, callback)
      watcher.start
      @watchers[watcher.id] = { watcher: watcher, callback: callback }
      watcher.id
    end

    def get(id)
      entry = @watchers[id]
      entry && entry[:watcher]
    end

    def stop(id)
      entry = @watchers.delete(id)
      entry&.dig(:watcher)&.stop
      !entry.nil?
    end

    # Drain every watcher and dispatch its events.
    def drain_all
      @watchers.each_value do |entry|
        watcher = entry[:watcher]
        watcher.drain.each do |ev|
          invoke(entry[:callback], nil, ev[:filename], ev[:events])
        end
      end
    end

    def shutdown
      @watchers.each_value { |e| e[:watcher].stop }
      @watchers.clear
    end

    def size
      @watchers.size
    end

    def empty?
      @watchers.empty?
    end

    # Never let a user callback take the editor down — log to
    # status_message and keep pumping.
    private def invoke(cb, *args)
      return if cb.nil?

      cb.call(*args)
    rescue StandardError => e
      @editor.status_message = "fs_event callback error: #{e.message}" if @editor.respond_to?(:status_message=)
    end
  end
end
