# frozen_string_literal: true

require_relative 'test_helper'

# Buffer-local keymaps: nvim_buf_set_keymap (Lua) or
# vim.keymap.set({ buffer = N }, ...) registers entries on the
# buffer's own Rvim::Keymap. Lookup tries the current buffer's
# local map first, then falls back to the editor's global map.

class TestBufferLocalKeymap < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @buf_a = Rvim::Buffer.new(@editor.next_buffer_id_bump!, '/tmp/a')
    @buf_a.lines = ['a-line']
    @buf_b = Rvim::Buffer.new(@editor.next_buffer_id_bump!, '/tmp/b')
    @buf_b.lines = ['b-line']
    @editor.register_buffer(@buf_a)
    @editor.register_buffer(@buf_b)
    @editor.swap_to_buffer(@buf_a)
  end

  # ----- Buffer helper -----

  def test_buffer_keymap_is_lazily_created
    fresh = Rvim::Buffer.new(99, nil)
    refute fresh.keymap?
    fresh.keymap.add(:normal, 'x', 'y')
    assert fresh.keymap?
  end

  # ----- Editor's chained lookup -----

  def test_local_exact_wins_over_global_prefix
    @editor.keymap.add(:normal, 'ab', 'GLOBAL')
    @buf_a.keymap.add(:normal, 'a', 'LOCAL')
    result, mapping = @editor.send(:chained_keymap_lookup, :normal, 'a')
    assert_equal :exact, result
    assert_equal 'LOCAL', mapping.rhs
  end

  def test_falls_through_to_global_when_local_does_not_match
    @editor.keymap.add(:normal, 'gd', 'GLOBAL_GD')
    @buf_a.keymap.add(:normal, 'xy', 'LOCAL_XY')
    result, mapping = @editor.send(:chained_keymap_lookup, :normal, 'gd')
    assert_equal :exact, result
    assert_equal 'GLOBAL_GD', mapping.rhs
  end

  def test_local_buffer_a_does_not_affect_buffer_b
    @buf_a.keymap.add(:normal, 'q', 'A_ONLY')
    @editor.swap_to_buffer(@buf_b)
    result, mapping = @editor.send(:chained_keymap_lookup, :normal, 'q')
    assert_equal :none, result
    assert_nil mapping
  end

  def test_prefix_status_considers_local_map
    @buf_a.keymap.add(:normal, 'foo', 'BAR')
    result, _ = @editor.send(:chained_keymap_lookup, :normal, 'fo')
    assert_equal :prefix, result
  end

  def test_lookup_works_without_local_keymap_present
    @editor.keymap.add(:normal, 'gg', 'TOP')
    result, mapping = @editor.send(:chained_keymap_lookup, :normal, 'gg')
    assert_equal :exact, result
    assert_equal 'TOP', mapping.rhs
  end
end

class TestLuaBufferLocalKeymap < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_vim_keymap_set_with_buffer_option_routes_to_buf_keymap
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.keymap.set('n', '<leader>q', ':qall<CR>', { buffer = 0 })
    LUA
    buf = @editor.current_buffer
    assert buf.keymap?, 'expected the new buffer to have local maps'
    # mapleader default is '\', so <leader>q expands to \q.
    found = false
    buf.keymap.each(:normal) { |lhs, _| found = true if lhs.start_with?("\\") }
    assert found, "expected a normal-mode entry — got: " + buf.keymap.instance_variable_get(:@table).inspect
  end

  def test_nvim_buf_set_keymap_with_specific_bufnr
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_keymap(buf, 'n', 'X', ':echo "x"<CR>', { noremap = true })
    LUA
    bufnr = @editor.lua.eval('return buf').to_i
    buf = @editor.buffers[bufnr]
    refute_nil buf
    assert buf.keymap?
    seen = []
    buf.keymap.each(:normal) { |lhs, _| seen << lhs }
    assert_includes seen, 'X'
  end

  def test_nvim_buf_del_keymap_removes_entry
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_keymap(buf, 'n', 'Y', 'yy', {})
      vim.api.nvim_buf_del_keymap(buf, 'n', 'Y')
    LUA
    bufnr = @editor.lua.eval('return buf').to_i
    buf = @editor.buffers[bufnr]
    seen = []
    buf.keymap.each(:normal) { |lhs, _| seen << lhs }
    refute_includes seen, 'Y'
  end

  def test_buffer_zero_means_current_buffer
    @editor.lua.eval(<<~LUA)
      a = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(a)
      vim.keymap.set('n', 'Q', 'qq', { buffer = 0 })
    LUA
    current = @editor.current_buffer
    assert current.keymap?
    seen = []
    current.keymap.each(:normal) { |lhs, _| seen << lhs }
    assert_includes seen, 'Q'
  end
end
