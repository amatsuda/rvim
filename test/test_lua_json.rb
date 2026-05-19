# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaJson < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_decode_object
    t = @editor.lua.eval(<<~LUA)
      local r = vim.json.decode('{"a":1,"b":"hi"}')
      return r.a .. "/" .. r.b
    LUA
    assert_equal '1/hi', t
  end

  def test_decode_array
    n = @editor.lua.eval(<<~LUA)
      local r = vim.json.decode('[10,20,30]')
      return r[1] + r[2] + r[3]
    LUA
    assert_equal 60, n.to_i
  end

  def test_decode_returns_nil_on_invalid
    res = @editor.lua.eval(<<~LUA)
      local r = vim.json.decode('not json')
      if r == nil then return "nil" else return "ok" end
    LUA
    assert_equal 'nil', res
  end

  def test_encode_object
    s = @editor.lua.eval('return vim.json.encode({ a = 1, b = "hi" })')
    parsed = JSON.parse(s)
    assert_equal({ 'a' => 1, 'b' => 'hi' }, parsed)
  end

  def test_encode_array
    s = @editor.lua.eval('return vim.json.encode({1, 2, 3})')
    assert_equal [1, 2, 3], JSON.parse(s)
  end

  def test_encode_nested
    s = @editor.lua.eval('return vim.json.encode({ outer = { inner = {1, 2} } })')
    assert_equal({ 'outer' => { 'inner' => [1, 2] } }, JSON.parse(s))
  end
end
