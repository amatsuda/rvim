# frozen_string_literal: true

require_relative 'test_helper'

# nvim_buf_attach (on_lines callback) + nvim_feedkeys. Telescope
# uses the former to refilter on every keystroke into its prompt
# buffer; many test helpers and macros rely on feedkeys to drive
# the editor as if from a real key sequence.

class TestBufferListeners < Test::Unit::TestCase
  def setup
    @buf = Rvim::Buffer.new(1, '/tmp/x')
    @buf.lines = ['hello']
  end

  def test_attach_listener_then_fire_invokes_callback
    captured = []
    @buf.attach_listener(->(*args) { captured << args })
    @buf.fire_lines_event(0, 1, 2)
    assert_equal 1, captured.size
    event, bufnr, _tick, first, last, new_last, _bc = captured.first
    assert_equal 'lines', event
    assert_equal 1, bufnr
    assert_equal 0, first
    assert_equal 1, last
    assert_equal 2, new_last
  end

  def test_listener_exceptions_are_swallowed
    @buf.attach_listener(->(*) { raise 'boom' })
    assert_nothing_raised { @buf.fire_lines_event(0, 0, 0) }
  end

  def test_detach_stops_future_fires
    cb = ->(*) { @hit = (@hit || 0) + 1 }
    @buf.attach_listener(cb)
    @buf.fire_lines_event(0, 0, 0)
    @buf.detach_listener(cb)
    @buf.fire_lines_event(0, 0, 0)
    assert_equal 1, @hit
  end
end

class TestLuaBufAttachAndFeedkeys < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_buf_attach_returns_true_when_on_lines_is_a_function
    ok = @editor.lua.eval(<<~LUA)
      local buf = vim.api.nvim_create_buf(false, true)
      return vim.api.nvim_buf_attach(buf, false, { on_lines = function() end })
    LUA
    assert_equal true, ok
  end

  def test_buf_attach_returns_false_without_on_lines
    ok = @editor.lua.eval(<<~LUA)
      local buf = vim.api.nvim_create_buf(false, true)
      return vim.api.nvim_buf_attach(buf, false, {})
    LUA
    assert_equal false, ok
  end

  def test_on_lines_fires_when_buffer_lines_change
    @editor.lua.eval(<<~LUA)
      hits = 0
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = function(_event, _bufnr, _tick, first, last, new_last)
          hits = hits + 1
          last_first = first
          last_new = new_last
        end,
      })
    LUA
    # Switch to the new buffer so capture_special_marks fires the listeners.
    bufnr = @editor.lua.eval('return bufnr').to_i
    @editor.swap_to_buffer(@editor.buffers[bufnr])
    # Drive an edit that changes lines: enter insert mode + type 'x'.
    pre = @editor.buffer_of_lines.dup
    @editor.buffer_of_lines[0] = 'x'
    @editor.send(:capture_special_marks, pre, :vi_command)
    assert_operator @editor.lua.eval('return hits').to_i, :>=, 1
  end

  def test_nvim_feedkeys_dispatches_each_char_to_editor_update
    # Use a fake update so we don't have to set up a full input env.
    seen = []
    @editor.define_singleton_method(:update) { |key| seen << key.char }
    @editor.lua.eval('vim.api.nvim_feedkeys("abc", "n", false)')
    assert_equal %w[a b c], seen
  end
end
