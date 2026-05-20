# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestCheckhealth < Test::Unit::TestCase
  def setup
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
    @editor = Rvim::Editor.new(Reline.core.config)
    @tmp = Dir.mktmpdir('rvim-health-')
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.exist?(@tmp)
  end

  def add_health_module(name, body)
    dir = File.join(@tmp, 'lua', name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'health.lua'), body)
    rtp = @editor.settings.get(:runtimepath).to_s
    @editor.settings.set(:runtimepath, "#{@tmp},#{rtp}") unless rtp.split(',').include?(@tmp)
    Rvim::Lua::Loader.refresh(@editor.lua.state, @editor)
  end

  def test_named_check_captures_all_kinds
    add_health_module('probe', <<~LUA)
      local M = {}
      function M.check()
        vim.health.start("section1")
        vim.health.ok("alpha")
        vim.health.warn("beta", "fix it")
        vim.health.error("gamma", { "line 1", "line 2" })
        vim.health.info("delta")
      end
      return M
    LUA
    Rvim::Command.execute(@editor, Rvim::Command.parse(':checkhealth probe'))
    body = @editor.buffer_of_lines.join("\n")
    assert_match(/## section1/, body)
    assert_match(/- OK: alpha/, body)
    assert_match(/- WARNING: beta/, body)
    assert_match(/fix it/, body)
    assert_match(/- ERROR: gamma/, body)
    assert_match(/line 1/, body)
    assert_match(/line 2/, body)
    assert_match(/- INFO: delta/, body)
  end

  def test_named_check_opens_dedicated_buffer
    add_health_module('probe', <<~LUA)
      local M = {}
      function M.check() vim.health.ok("hi") end
      return M
    LUA
    Rvim::Command.execute(@editor, Rvim::Command.parse(':checkhealth probe'))
    assert_equal '[health]', @editor.current_buffer.filepath
    assert @editor.current_buffer.scratch
  end

  def test_bare_form_discovers_modules_on_rtp
    add_health_module('alpha', "local M={}; function M.check() vim.health.ok('a-ok') end; return M\n")
    add_health_module('beta',  "local M={}; function M.check() vim.health.ok('b-ok') end; return M\n")
    Rvim::Command.execute(@editor, Rvim::Command.parse(':checkhealth'))
    body = @editor.buffer_of_lines.join("\n")
    assert_match(/alpha\.health/, body)
    assert_match(/beta\.health/, body)
    assert_match(/a-ok/, body)
    assert_match(/b-ok/, body)
  end

  def test_check_function_crash_is_reported_not_raised
    add_health_module('boom', <<~LUA)
      local M = {}
      function M.check()
        vim.health.start("boom")
        error("kaboom")
      end
      return M
    LUA
    assert_nothing_raised do
      Rvim::Command.execute(@editor, Rvim::Command.parse(':checkhealth boom'))
    end
    body = @editor.buffer_of_lines.join("\n")
    assert_match(/check\(\) crashed/, body)
    assert_match(/kaboom/, body)
  end

  def test_missing_module_reports_error
    Rvim::Command.execute(@editor, Rvim::Command.parse(':checkhealth nonexistent'))
    body = @editor.buffer_of_lines.join("\n")
    assert_match(/failed to load nonexistent\.health/, body)
  end

  def test_module_without_check_function_reports_error
    add_health_module('nocheck', "return {}\n")
    Rvim::Command.execute(@editor, Rvim::Command.parse(':checkhealth nocheck'))
    body = @editor.buffer_of_lines.join("\n")
    assert_match(/has no check\(\) function/, body)
  end

  def test_full_module_name_passed_through
    # Allow callers to spell the full module name (with .health) too.
    add_health_module('explicit', <<~LUA)
      local M = {}
      function M.check() vim.health.ok("explicit") end
      return M
    LUA
    Rvim::Command.execute(@editor, Rvim::Command.parse(':checkhealth explicit.health'))
    body = @editor.buffer_of_lines.join("\n")
    assert_match(/explicit/, body)
    assert_match(/- OK: explicit/, body)
  end
end
