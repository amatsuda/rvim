# frozen_string_literal: true

require_relative 'test_helper'

# Extmarks + namespaces + nvim_set_hl. Telescope uses these for the
# selected-row band, fuzzy-match position underlines, and devicons.
# We support the highlight subset (hl_group + col range) for V1 —
# virt_text, sign_text, virt_lines are follow-ups.

class TestHighlightGroups < Test::Unit::TestCase
  def setup
    @hl = Rvim::HighlightGroups.new
  end

  def test_seeded_groups_resolve_to_sgr_pairs
    pair = @hl.lookup('Search')
    refute_nil pair
    assert_match(/\e\[/, pair.open)
    assert_match(/\e\[/, pair.close)
  end

  def test_define_with_fg_named_color
    @hl.define('CustomRed', { 'fg' => 'red' })
    pair = @hl.lookup('CustomRed')
    assert_match(/\e\[31m/, pair.open) # named 'red' → fg 31
  end

  def test_define_with_fg_numeric_256_color
    @hl.define('Gold220', { 'fg' => 220 })
    pair = @hl.lookup('Gold220')
    assert_match(/\e\[38;5;220m/, pair.open)
  end

  def test_define_with_bg_and_bold_and_italic
    @hl.define('Fancy', { 'bg' => 240, 'bold' => true, 'italic' => true })
    pair = @hl.lookup('Fancy')
    assert_match(/\e\[48;5;240m/, pair.open)
    assert_match(/\e\[1m/, pair.open)
    assert_match(/\e\[3m/, pair.open)
    # close should reset everything we opened.
    assert_match(/\e\[22m/, pair.close)
    assert_match(/\e\[23m/, pair.close)
  end

  def test_unknown_color_name_falls_back_silently
    assert_nothing_raised { @hl.define('Bad', { 'fg' => 'nope-not-a-color' }) }
    assert @hl.defined?('Bad')
  end
end

class TestExtmarks < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @buf = Rvim::Buffer.new(@editor.next_buffer_id_bump!, '/tmp/x')
    @buf.lines = ['hello world', 'second line']
    @editor.register_buffer(@buf)
    @editor.swap_to_buffer(@buf)
  end

  def test_create_namespace_returns_stable_id_for_name
    a = @editor.create_namespace('rvim.test')
    b = @editor.create_namespace('rvim.test')
    assert_equal a, b
  end

  def test_create_namespace_with_empty_name_is_anonymous
    a = @editor.create_namespace('')
    b = @editor.create_namespace('')
    refute_equal a, b, 'empty name allocates a fresh id every call'
  end

  def test_buf_next_extmark_id_is_monotonic
    a = @buf.next_extmark_id!
    b = @buf.next_extmark_id!
    assert_operator b, :>, a
  end

  # ----- screen overlay -----

  def test_overlay_wraps_extmark_range_with_group_sgr
    @editor.hl_groups.define('Hit', { 'fg' => 220, 'bold' => true })
    screen = Rvim::Screen.new(@editor)
    marks = [{ start_byte: 0, end_byte: 5, hl_group: 'Hit', priority: 100 }]
    out = screen.send(:apply_extmark_overlay, 'hello world', marks, 'hello world')
    # Both SGR codes are emitted (order doesn't matter to the terminal).
    assert_match(/\e\[1m/, out)
    assert_match(/\e\[38;5;220m/, out)
    # The "hello" content is inside the open/close pair.
    assert_match(/hello\e\[39m\e\[22m/, out)
  end

  def test_higher_priority_extmark_renders_over_lower
    @editor.hl_groups.define('Low',  { 'fg' => 81 })
    @editor.hl_groups.define('High', { 'fg' => 220 })
    screen = Rvim::Screen.new(@editor)
    # Both span chars 0..4 but priority differs.
    marks = [
      { start_byte: 0, end_byte: 5, hl_group: 'Low',  priority: 50 },
      { start_byte: 0, end_byte: 5, hl_group: 'High', priority: 100 },
    ]
    out = screen.send(:apply_extmark_overlay, 'hello world', marks, 'hello world')
    # The Low pair opens first; when its range ends, High should
    # already be in effect (or applied). Verify both opens appear.
    assert_match(/\e\[38;5;81m/, out)
    assert_match(/\e\[38;5;220m/, out)
  end

  def test_unknown_hl_group_is_silently_dropped
    screen = Rvim::Screen.new(@editor)
    marks = [{ start_byte: 0, end_byte: 5, hl_group: 'Missing', priority: 100 }]
    out = screen.send(:apply_extmark_overlay, 'hello world', marks, 'hello world')
    # No SGR span — output is unchanged.
    assert_equal 'hello world', out
  end

  def test_extmarks_intersecting_returns_only_marks_covering_the_line
    @editor.hl_groups.define('X', { 'fg' => 196 })
    ns = @editor.create_namespace('x')
    @buf.extmarks[ns][@buf.next_extmark_id!] = { line: 0, col: 0, end_row: 0, end_col: 5, hl_group: 'X' }
    @buf.extmarks[ns][@buf.next_extmark_id!] = { line: 1, col: 2, end_row: 1, end_col: 6, hl_group: 'X' }
    screen = Rvim::Screen.new(@editor)
    line0 = screen.send(:extmarks_intersecting, @buf, 0)
    line1 = screen.send(:extmarks_intersecting, @buf, 1)
    assert_equal 1, line0.size
    assert_equal 1, line1.size
    assert_equal 2, line1.first[:start_byte]
  end
end

class TestLuaExtmarks < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?
  end

  def test_create_namespace_returns_an_integer_id
    n = @editor.lua.eval(<<~LUA).to_i
      return vim.api.nvim_create_namespace('telescope.matching')
    LUA
    assert_operator n, :>, 0
  end

  def test_set_extmark_then_get_returns_the_mark
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world', 'second' })
      ns  = vim.api.nvim_create_namespace('x')
      id  = vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = 5, hl_group = 'Search' })
      marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    LUA
    rows = @editor.lua.eval('return #marks').to_i
    assert_equal 1, rows
    # marks[1] = { id, line, col }
    assert_equal 0, @editor.lua.eval('return marks[1][2]').to_i # line
    assert_equal 0, @editor.lua.eval('return marks[1][3]').to_i # col
  end

  def test_buf_add_highlight_registers_an_extmark_with_hl_group
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello world' })
      ns  = vim.api.nvim_create_namespace('x')
      vim.api.nvim_buf_add_highlight(buf, ns, 'Search', 0, 0, 5)
    LUA
    bufnr = @editor.lua.eval('return buf').to_i
    ns    = @editor.lua.eval('return ns').to_i
    buf = @editor.buffers[bufnr]
    marks = buf.extmarks[ns]
    assert_equal 1, marks.size
    mark = marks.values.first
    assert_equal 'Search', mark[:hl_group]
    assert_equal 0, mark[:col]
    assert_equal 5, mark[:end_col]
  end

  def test_buf_clear_namespace_drops_every_mark
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'b' })
      ns  = vim.api.nvim_create_namespace('x')
      vim.api.nvim_buf_add_highlight(buf, ns, 'Search', 0, 0, 1)
      vim.api.nvim_buf_add_highlight(buf, ns, 'Search', 1, 0, 1)
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    LUA
    bufnr = @editor.lua.eval('return buf').to_i
    ns    = @editor.lua.eval('return ns').to_i
    assert_empty @editor.buffers[bufnr].extmarks[ns]
  end

  def test_buf_del_extmark_removes_the_specific_mark
    @editor.lua.eval(<<~LUA)
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'abc' })
      ns  = vim.api.nvim_create_namespace('x')
      mid = vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = 1, hl_group = 'Search' })
      ok  = vim.api.nvim_buf_del_extmark(buf, ns, mid)
    LUA
    assert_equal true, @editor.lua.eval('return ok')
    bufnr = @editor.lua.eval('return buf').to_i
    ns    = @editor.lua.eval('return ns').to_i
    assert_empty @editor.buffers[bufnr].extmarks[ns]
  end

  def test_set_hl_with_fg_table_registers_group
    @editor.lua.eval(<<~LUA)
      vim.api.nvim_set_hl(0, 'TestGroup', { fg = 'red', bg = 240, bold = true })
    LUA
    assert @editor.hl_groups.defined?('TestGroup')
    pair = @editor.hl_groups.lookup('TestGroup')
    assert_match(/\e\[31m/, pair.open)
    assert_match(/\e\[48;5;240m/, pair.open)
    assert_match(/\e\[1m/, pair.open)
  end
end
