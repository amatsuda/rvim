# frozen_string_literal: true

module Rvim
  # Filesystem watcher. Polls a path's stat info on a background
  # thread and emits change / rename events into a thread-safe queue
  # for the main thread to drain.
  #
  # We poll rather than use libuv's inotify / FSEvents because:
  #   - Zero extra runtime dependencies.
  #   - rvim users typically watch a handful of configs (init.vim,
  #     a .rvimrc, project-local rcfiles), not whole worktrees, so
  #     the per-tick cost is negligible.
  #
  # API matches `libuv`-style fs_event semantics so the Lua surface
  # (vim.uv.new_fs_event() -> handle:start(path, opts, cb)) is a
  # direct wrap.
  class FsWatcher
    DEFAULT_INTERVAL_MS = 200

    attr_reader :id, :path

    @@next_id = 0
    @@id_mutex = Mutex.new

    def self.allocate_id
      @@id_mutex.synchronize { @@next_id += 1 }
    end

    def initialize(path, opts: {})
      @path = File.expand_path(path.to_s)
      @opts = stringify(opts)
      @id = self.class.allocate_id
      @queue = Thread::Queue.new
      @stopped = false
    end

    def start
      @prev_snapshot = snapshot
      @thread = Thread.new { poll_loop }
      self
    end

    def stop
      @stopped = true
      @thread&.join(0.5)
      @thread = nil
    end

    def close
      stop
    end

    # Pop all currently-available events without blocking. Each
    # event is a Hash with :filename and :events keys; events is
    # a Hash with `change:` / `rename:` boolean flags (libuv shape).
    def drain
      out = []
      out << @queue.pop(true) until @queue.empty?
      out
    rescue ThreadError
      out
    end

    def stopped?
      @stopped
    end

    private def poll_loop
      interval = ((@opts['interval'] || DEFAULT_INTERVAL_MS).to_f / 1000.0)
      until @stopped
        sleep interval
        break if @stopped

        cur = snapshot
        diff_events(@prev_snapshot, cur).each { |ev| @queue << ev }
        @prev_snapshot = cur
      end
    rescue StandardError
      # Defensive — never let a watcher thread blow up the editor.
      nil
    end

    # Returns Hash{ relative_path => [mtime, size] } for the watched
    # path. For a regular file: one entry keyed by ''. For a
    # directory: one entry per immediate child (or recursively when
    # opts['recursive'] is set).
    private def snapshot
      return {} unless File.exist?(@path) || File.symlink?(@path)

      out = {}
      if File.directory?(@path)
        list_entries.each do |rel|
          full = File.join(@path, rel)
          out[rel] = stat_pair(full)
        end
      else
        out[''] = stat_pair(@path)
      end
      out
    end

    private def list_entries
      if @opts['recursive']
        Dir.glob('**/*', base: @path)
      else
        Dir.children(@path)
      end
    rescue Errno::ENOENT
      []
    end

    private def stat_pair(path)
      s = File.stat(path)
      [s.mtime.to_f, s.size]
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    # Compare two snapshots and yield libuv-shape events. New /
    # removed entries are `rename`; mtime / size delta is `change`.
    private def diff_events(prev, cur)
      events = []
      (prev.keys | cur.keys).each do |rel|
        before = prev[rel]
        after  = cur[rel]
        if before.nil? && after
          events << event(rel, rename: true)
        elsif before && after.nil?
          events << event(rel, rename: true)
        elsif before != after
          events << event(rel, change: true)
        end
      end
      events
    end

    private def event(rel, change: false, rename: false)
      flags = {}
      flags[:change] = true if change
      flags[:rename] = true if rename
      { filename: rel.to_s, events: flags }
    end

    private def stringify(opts)
      case opts
      when Hash then opts.transform_keys(&:to_s)
      else {}
      end
    end
  end
end
