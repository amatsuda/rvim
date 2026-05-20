# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaFn < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_fn_getcwd
    assert_equal Dir.pwd, @editor.lua.eval('return vim.fn.getcwd()')
  end

  def test_fn_has_returns_1_for_known
    assert_equal 1, @editor.lua.eval('return vim.fn.has("lua")').to_i
  end

  def test_fn_has_returns_0_for_unknown
    assert_equal 0, @editor.lua.eval('return vim.fn.has("not_a_real_feature_xyz")').to_i
  end

  def test_fn_has_nvim_returns_1
    # rvim presents itself as NeoVim-compatible so plugins that
    # gate on has("nvim") take the modern path.
    assert_equal 1, @editor.lua.eval('return vim.fn.has("nvim")').to_i
  end

  def test_fn_has_nvim_version_gate_accepts_versions_we_claim
    # lazy.nvim probes has("nvim-0.8.0"); we claim 0.10 so anything
    # at-or-below should return 1.
    %w[nvim-0 nvim-0.7 nvim-0.8.0 nvim-0.9.5 nvim-0.10 nvim-0.11.0].each do |feat|
      assert_equal 1, @editor.lua.eval(%(return vim.fn.has("#{feat}"))).to_i, "expected has(#{feat}) == 1"
    end
  end

  def test_fn_has_nvim_version_gate_rejects_future_versions
    %w[nvim-0.12 nvim-0.99 nvim-1.0 nvim-2].each do |feat|
      assert_equal 0, @editor.lua.eval(%(return vim.fn.has("#{feat}"))).to_i, "expected has(#{feat}) == 0"
    end
  end

  def test_fn_filereadable
    Tempfile.create('lua-fn') do |f|
      assert_equal 1, @editor.lua.eval(%(return vim.fn.filereadable("#{f.path}"))).to_i
    end
    assert_equal 0, @editor.lua.eval('return vim.fn.filereadable("/nonexistent/xyz")').to_i
  end

  def test_fn_isdirectory
    assert_equal 1, @editor.lua.eval('return vim.fn.isdirectory("/")').to_i
    assert_equal 0, @editor.lua.eval('return vim.fn.isdirectory("/nonexistent_xyz")').to_i
  end

  def test_fn_fnamemodify_extension
    assert_equal 'rb', @editor.lua.eval('return vim.fn.fnamemodify("/tmp/x.rb", ":e")')
  end

  def test_fn_fnamemodify_head
    assert_equal '/tmp', @editor.lua.eval('return vim.fn.fnamemodify("/tmp/x.rb", ":h")')
  end

  def test_fn_fnamemodify_tail
    assert_equal 'x.rb', @editor.lua.eval('return vim.fn.fnamemodify("/tmp/x.rb", ":t")')
  end

  def test_fn_fnamemodify_root
    assert_equal '/tmp/x', @editor.lua.eval('return vim.fn.fnamemodify("/tmp/x.rb", ":r")')
  end

  def test_fn_line_dot
    @editor.instance_variable_set(:@buffer_of_lines, [+'a', +'b', +'c'])
    @editor.instance_variable_set(:@line_index, 1)
    assert_equal 2, @editor.lua.eval('return vim.fn.line(".")').to_i
  end

  def test_fn_line_dollar
    @editor.instance_variable_set(:@buffer_of_lines, [+'a', +'b', +'c'])
    assert_equal 3, @editor.lua.eval('return vim.fn.line("$")').to_i
  end

  def test_fn_mode
    assert_equal 'n', @editor.lua.eval('return vim.fn.mode()')
  end

  def test_fn_split
    res = @editor.lua.eval('return vim.fn.split("a,b,c", ",")')
    assert_equal({ 1.0 => 'a', 2.0 => 'b', 3.0 => 'c' }, res.to_h)
  end

  def test_fn_join
    res = @editor.lua.eval('return vim.fn.join({"a","b","c"}, "-")')
    assert_equal 'a-b-c', res
  end

  def test_fn_substitute_global
    res = @editor.lua.eval('return vim.fn.substitute("foo bar foo", "foo", "baz", "g")')
    assert_equal 'baz bar baz', res
  end

  def test_fn_tolower_toupper
    assert_equal 'abc', @editor.lua.eval('return vim.fn.tolower("ABC")')
    assert_equal 'ABC', @editor.lua.eval('return vim.fn.toupper("abc")')
  end

  def test_fn_trim
    assert_equal 'abc', @editor.lua.eval('return vim.fn.trim("  abc  ")')
  end

  def test_fn_min_max
    assert_equal 1, @editor.lua.eval('return vim.fn.min({3,1,2})').to_i
    assert_equal 3, @editor.lua.eval('return vim.fn.max({3,1,2})').to_i
  end

  def test_fn_empty
    assert_equal 1, @editor.lua.eval('return vim.fn.empty("")').to_i
    assert_equal 1, @editor.lua.eval('return vim.fn.empty(0)').to_i
    assert_equal 0, @editor.lua.eval('return vim.fn.empty("x")').to_i
  end

  def test_fn_len
    assert_equal 3, @editor.lua.eval('return vim.fn.len("abc")').to_i
    assert_equal 3, @editor.lua.eval('return vim.fn.len({1,2,3})').to_i
  end

  def test_fn_shellescape
    assert_equal "'hello'", @editor.lua.eval('return vim.fn.shellescape("hello")')
  end

  def test_fn_stdpath_config
    config = @editor.lua.eval('return vim.fn.stdpath("config")')
    assert_match(/rvim/, config)
  end

  def test_fn_stdpath_all_known_what
    %w[config data cache state log run].each do |what|
      path = @editor.lua.eval(%(return vim.fn.stdpath("#{what}")))
      refute_empty path, "#{what} should be non-empty"
      assert_match(%r{rvim|tmp/rvim}, path, "#{what} should reference rvim")
    end
  end

  def test_fn_stdpath_respects_xdg_env
    prev = ENV['XDG_CONFIG_HOME']
    ENV['XDG_CONFIG_HOME'] = '/tmp/xdg-test'
    assert_equal '/tmp/xdg-test/rvim', @editor.lua.eval('return vim.fn.stdpath("config")')
  ensure
    ENV['XDG_CONFIG_HOME'] = prev
  end

  def test_fn_stdpath_unknown_returns_empty
    assert_equal '', @editor.lua.eval('return vim.fn.stdpath("nope")')
  end

  def test_fn_executable_yes_no
    assert_equal 1, @editor.lua.eval('return vim.fn.executable("ls")').to_i
    assert_equal 0, @editor.lua.eval('return vim.fn.executable("nonexistent_xyz_12345")').to_i
  end
end
