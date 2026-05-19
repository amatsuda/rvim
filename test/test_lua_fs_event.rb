# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

# Lua-level integration: vim.uv.new_fs_event handle:start / :stop /
# :close. Real filesystem changes drive events; the test pumps the
# registry to dispatch callbacks.

class TestLuaFsEvent < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?

    @tmpdir = Dir.mktmpdir('rvim-luafs-test')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir
  end

  def wait_for(timeout: 2.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      break false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      @editor.pump_fs_events
      sleep 0.02
    end
    true
  end

  def test_new_fs_event_returns_a_handle_with_start_stop_close
    @editor.lua.eval(<<~LUA)
      h = vim.uv.new_fs_event()
    LUA
    assert_equal true, @editor.lua.eval('return type(h.start) == "function"')
    assert_equal true, @editor.lua.eval('return type(h.stop)  == "function"')
    assert_equal true, @editor.lua.eval('return type(h.close) == "function"')
  end

  def test_start_fires_callback_on_file_change
    file = File.join(@tmpdir, 'a.txt')
    File.write(file, 'before')
    @editor.lua.eval(<<~LUA)
      events_seen = {}
      h = vim.uv.new_fs_event()
      h:start('#{file}', { interval = 30 }, function(err, filename, events)
        table.insert(events_seen, { err, filename, events.change == true, events.rename == true })
      end)
    LUA
    sleep 0.1
    File.write(file, 'after')
    wait_for { @editor.lua.eval('return #events_seen >= 1') == true }
    @editor.lua.eval('h:stop()')
    assert_operator @editor.lua.eval('return #events_seen').to_i, :>=, 1
  end

  def test_start_fires_rename_on_new_file_in_directory
    @editor.lua.eval(<<~LUA)
      events_seen = {}
      h = vim.uv.new_fs_event()
      h:start('#{@tmpdir}', { interval = 30 }, function(err, filename, events)
        if events.rename and filename == 'fresh.txt' then
          table.insert(events_seen, filename)
        end
      end)
    LUA
    sleep 0.1
    File.write(File.join(@tmpdir, 'fresh.txt'), 'x')
    wait_for { @editor.lua.eval('return #events_seen >= 1') == true }
    @editor.lua.eval('h:stop()')
    assert_equal 'fresh.txt', @editor.lua.eval('return events_seen[1]')
  end

  def test_stop_halts_the_callback
    file = File.join(@tmpdir, 'b.txt')
    File.write(file, 'x')
    @editor.lua.eval(<<~LUA)
      hit = 0
      h = vim.uv.new_fs_event()
      h:start('#{file}', { interval = 30 }, function() hit = hit + 1 end)
    LUA
    sleep 0.1
    @editor.lua.eval('h:stop()')
    sleep 0.1
    File.write(file, 'y')
    sleep 0.2
    @editor.pump_fs_events
    assert_equal 0, @editor.lua.eval('return hit').to_i
  end

  def test_close_releases_the_handle_id
    @editor.lua.eval(<<~LUA)
      h = vim.uv.new_fs_event()
      h:start('#{@tmpdir}', { interval = 30 }, function() end)
      first_id = h._id
      h:close()
      cleared_id = h._id
    LUA
    refute_nil @editor.lua.eval('return first_id')
    assert_nil @editor.lua.eval('return cleared_id')
  end
end
