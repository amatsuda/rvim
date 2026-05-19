# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

# Rvim::FsWatcher: polls a path's stat info on a background thread,
# emits libuv-shape change / rename events. Real filesystem tests
# use a tmpdir; the poll interval is shortened so changes show up
# within reasonable test time.

class TestFsWatcher < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir('rvim-fswatch-test')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def make_watcher(path, opts: {})
    Rvim::FsWatcher.new(path, opts: { 'interval' => 30 }.merge(opts))
  end

  def wait_for_events(watcher, min_count: 1, timeout: 2.0)
    out = []
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      out.concat(watcher.drain)
      break out if out.size >= min_count
      break out if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.02
    end
  end

  def test_id_is_monotonic
    a = make_watcher(@tmpdir)
    b = make_watcher(@tmpdir)
    assert_operator b.id, :>, a.id
  end

  def test_emits_change_when_file_mtime_or_size_changes
    file = File.join(@tmpdir, 'a.txt')
    File.write(file, 'hello')
    w = make_watcher(file)
    w.start
    sleep 0.1
    File.write(file, 'hello world!')
    events = wait_for_events(w)
    w.stop
    assert(events.any? { |e| e[:events][:change] }, "expected a change event, got #{events.inspect}")
  end

  def test_emits_rename_when_new_file_appears_in_dir
    w = make_watcher(@tmpdir)
    w.start
    sleep 0.1
    File.write(File.join(@tmpdir, 'new.txt'), 'x')
    events = wait_for_events(w)
    w.stop
    hit = events.find { |e| e[:filename] == 'new.txt' && e[:events][:rename] }
    refute_nil hit, "expected rename for new.txt, got #{events.inspect}"
  end

  def test_emits_rename_when_file_is_removed_from_dir
    file = File.join(@tmpdir, 'gone.txt')
    File.write(file, 'x')
    w = make_watcher(@tmpdir)
    w.start
    sleep 0.1
    File.delete(file)
    events = wait_for_events(w)
    w.stop
    hit = events.find { |e| e[:filename] == 'gone.txt' && e[:events][:rename] }
    refute_nil hit
  end

  def test_recursive_picks_up_nested_changes
    sub = File.join(@tmpdir, 'sub')
    Dir.mkdir(sub)
    w = make_watcher(@tmpdir, opts: { 'recursive' => true })
    w.start
    sleep 0.1
    File.write(File.join(sub, 'deep.txt'), 'x')
    events = wait_for_events(w)
    w.stop
    hit = events.find { |e| e[:filename].include?('deep.txt') && e[:events][:rename] }
    refute_nil hit
  end

  def test_stop_halts_the_polling_thread
    w = make_watcher(@tmpdir)
    w.start
    w.stop
    sleep 0.1
    File.write(File.join(@tmpdir, 'late.txt'), 'x')
    sleep 0.1
    assert_empty w.drain, 'no events after stop'
  end

  def test_drain_returns_empty_when_nothing_changed
    w = make_watcher(@tmpdir)
    w.start
    sleep 0.1
    assert_empty w.drain
    w.stop
  end

  def test_watcher_on_missing_path_does_not_crash
    w = make_watcher(File.join(@tmpdir, 'does-not-exist'))
    assert_nothing_raised do
      w.start
      sleep 0.1
      w.stop
    end
  end
end
