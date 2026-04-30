# frozen_string_literal: true

require_relative 'test_helper'

class TestLuaLspStub < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_lsp_get_clients_returns_empty_array
    res = @editor.lua.eval('return vim.lsp.get_clients()')
    assert_equal({}, res.to_h)
  end

  def test_lsp_buf_get_clients_returns_empty
    res = @editor.lua.eval('return vim.lsp.buf_get_clients(0)')
    assert_equal({}, res.to_h)
  end

  def test_lsp_start_returns_nil
    assert_nil @editor.lua.eval('return vim.lsp.start({ name = "fake" })')
  end

  def test_lsp_buf_methods_are_callable
    @editor.lua.eval('vim.lsp.buf.hover()')
    @editor.lua.eval('vim.lsp.buf.definition()')
    @editor.lua.eval('vim.lsp.buf.format()')
    # No assertion error means the no-ops are wired.
    assert true
  end

  def test_lsp_protocol_table_exists
    refute_nil @editor.lua.eval('return vim.lsp.protocol')
  end

  def test_lsp_log_levels
    assert_equal 4, @editor.lua.eval('return vim.lsp.log_levels.ERROR').to_i
  end

  def test_diagnostic_get_returns_empty
    res = @editor.lua.eval('return vim.diagnostic.get(0)')
    assert_equal({}, res.to_h)
  end

  def test_diagnostic_severity_constants
    assert_equal 1, @editor.lua.eval('return vim.diagnostic.severity.ERROR').to_i
    assert_equal 4, @editor.lua.eval('return vim.diagnostic.severity.HINT').to_i
  end

  def test_diagnostic_no_op_methods_are_callable
    @editor.lua.eval('vim.diagnostic.config({ virtual_text = true })')
    @editor.lua.eval('vim.diagnostic.set(1, 0, {})')
    @editor.lua.eval('vim.diagnostic.show(1, 0)')
    @editor.lua.eval('vim.diagnostic.goto_next()')
    assert true
  end

  def test_lsp_inlay_hint_is_disabled
    assert_equal false, @editor.lua.eval('return vim.lsp.inlay_hint.is_enabled()')
  end

  def test_plugin_probe_pattern_works
    # Many plugins do this:
    #   if #vim.lsp.get_clients() == 0 then return end
    # Verify it short-circuits cleanly with no error.
    res = @editor.lua.eval(<<~LUA)
      local clients = vim.lsp.get_clients()
      if not clients or #clients == 0 then
        return "no_lsp"
      end
      return "had_lsp"
    LUA
    assert_equal 'no_lsp', res
  end
end
