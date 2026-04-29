# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaUi < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_ui_input_default_passes_default
    @editor.lua.eval(<<~LUA)
      result = nil
      vim.ui.input({ prompt = "name?", default = "alice" }, function(v) result = v end)
    LUA
    assert_equal 'alice', @editor.lua.eval('return result')
  end

  def test_ui_input_no_default_passes_nil
    @editor.lua.eval(<<~LUA)
      result = "untouched"
      vim.ui.input({ prompt = "name?" }, function(v) result = v end)
    LUA
    assert_nil @editor.lua.eval('return result')
  end

  def test_ui_select_picks_first_item
    @editor.lua.eval(<<~LUA)
      picked = nil
      idx = nil
      vim.ui.select({"a", "b", "c"}, {}, function(item, i) picked = item; idx = i end)
    LUA
    assert_equal 'a', @editor.lua.eval('return picked')
    assert_equal 1.0, @editor.lua.eval('return idx')
  end

  def test_ui_select_empty_items_passes_nil
    @editor.lua.eval(<<~LUA)
      picked = "untouched"
      vim.ui.select({}, {}, function(item, i) picked = item end)
    LUA
    assert_nil @editor.lua.eval('return picked')
  end

  def test_ui_input_can_be_overridden_by_plugin
    @editor.lua.eval(<<~LUA)
      vim.ui.input = function(opts, cb) cb("OVERRIDDEN") end
      result = nil
      vim.ui.input({}, function(v) result = v end)
    LUA
    assert_equal 'OVERRIDDEN', @editor.lua.eval('return result')
  end
end
