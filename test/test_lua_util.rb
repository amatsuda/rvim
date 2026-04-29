# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaUtil < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_tbl_isempty
    assert_equal true, @editor.lua.eval('return vim.tbl_isempty({})')
    assert_equal false, @editor.lua.eval('return vim.tbl_isempty({1,2})')
  end

  def test_tbl_islist
    assert_equal true, @editor.lua.eval('return vim.tbl_islist({1,2,3})')
    assert_equal false, @editor.lua.eval('return vim.tbl_islist({a=1, b=2})')
  end

  def test_tbl_count
    assert_equal 3, @editor.lua.eval('return vim.tbl_count({a=1, b=2, c=3})').to_i
  end

  def test_tbl_keys_and_values
    assert_equal 3, @editor.lua.eval('return #vim.tbl_keys({a=1,b=2,c=3})').to_i
    assert_equal 3, @editor.lua.eval('return #vim.tbl_values({a=1,b=2,c=3})').to_i
  end

  def test_tbl_contains
    assert_equal true, @editor.lua.eval('return vim.tbl_contains({1,2,3}, 2)')
    assert_equal false, @editor.lua.eval('return vim.tbl_contains({1,2,3}, 99)')
  end

  def test_tbl_extend_force
    res = @editor.lua.eval('return vim.tbl_extend("force", {a=1}, {a=2, b=3})')
    h = res.to_h
    assert_equal 2.0, h['a']
    assert_equal 3.0, h['b']
  end

  def test_tbl_extend_keep
    res = @editor.lua.eval('return vim.tbl_extend("keep", {a=1}, {a=2, b=3})')
    h = res.to_h
    assert_equal 1.0, h['a']
    assert_equal 3.0, h['b']
  end

  def test_tbl_deep_extend_merges_nested
    res = @editor.lua.eval('return vim.tbl_deep_extend("force", {a={x=1}}, {a={y=2}}).a')
    h = res.to_h
    assert_equal 1.0, h['x']
    assert_equal 2.0, h['y']
  end

  def test_list_extend
    res = @editor.lua.eval('return vim.list_extend({1,2}, {3,4})')
    assert_equal [1.0, 2.0, 3.0, 4.0], res.to_h.values
  end

  def test_split_default
    res = @editor.lua.eval('return vim.split("a,b,c", ",")')
    assert_equal ['a', 'b', 'c'], res.to_h.values
  end

  def test_split_trimempty
    res = @editor.lua.eval('return vim.split(",a,b,", ",", { trimempty = true })')
    assert_equal ['a', 'b'], res.to_h.values
  end

  def test_startswith
    assert_equal true, @editor.lua.eval('return vim.startswith("hello", "he")')
    assert_equal false, @editor.lua.eval('return vim.startswith("hello", "lo")')
  end

  def test_endswith
    assert_equal true, @editor.lua.eval('return vim.endswith("hello", "lo")')
    assert_equal false, @editor.lua.eval('return vim.endswith("hello", "he")')
  end

  def test_trim
    assert_equal 'abc', @editor.lua.eval('return vim.trim("   abc   ")')
  end

  def test_deepcopy
    @editor.lua.eval(<<~LUA)
      a = {x = {y = 1}}
      b = vim.deepcopy(a)
      b.x.y = 99
    LUA
    assert_equal 1, @editor.lua.eval('return a.x.y').to_i
  end

  def test_tbl_map
    res = @editor.lua.eval('return vim.tbl_map(function(v) return v * 2 end, {1,2,3})')
    assert_equal [2.0, 4.0, 6.0], res.to_h.values
  end

  def test_tbl_filter
    res = @editor.lua.eval('return vim.tbl_filter(function(v) return v > 1 end, {1,2,3})')
    assert_equal [2.0, 3.0], res.to_h.values
  end
end
