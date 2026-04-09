# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

FakeBuffer = Struct.new(:lines, :folds)

class TestFoldsStorage < Test::Unit::TestCase
  def setup
    @folds = Rvim::Folds.new
  end

  def test_add_returns_fold
    f = @folds.add(0, 4)
    assert_not_nil f
    assert_equal 0, f.start_line
    assert_equal 4, f.end_line
    assert_equal true, f.closed
  end

  def test_add_rejects_inverted_range
    assert_nil @folds.add(5, 2)
  end

  def test_add_rejects_partial_overlap
    @folds.add(0, 4)
    assert_nil @folds.add(2, 6)
    assert_equal 1, @folds.size
  end

  def test_add_allows_nested_containment
    @folds.add(0, 10)
    inner = @folds.add(2, 5)
    refute_nil inner
    assert_equal 2, @folds.size
  end

  def test_at_line_returns_innermost
    @folds.add(0, 10)
    @folds.add(2, 5)
    f = @folds.at_line(3)
    assert_equal 2, f.start_line
    assert_equal 5, f.end_line
  end

  def test_hidden_when_outer_closed_hides_inner_start
    @folds.add(0, 10, closed: true) # outer closed
    @folds.add(2, 5, closed: false) # inner open
    # Line 2 is the inner's start_line, but the outer is closed and contains it
    assert_equal true, @folds.hidden?(2)
    assert_equal true, @folds.hidden?(5)
    # Line 0 is outer's start — still visible
    assert_equal false, @folds.hidden?(0)
  end

  def test_hidden_when_inner_closed_outer_open
    @folds.add(0, 10, closed: false)
    @folds.add(2, 5, closed: true)
    assert_equal false, @folds.hidden?(2) # inner's start_line visible
    assert_equal true, @folds.hidden?(3)  # inside closed inner
    assert_equal false, @folds.hidden?(7) # inside outer (open), past inner
  end

  def test_add_allows_adjacent_disjoint
    @folds.add(0, 2)
    assert_not_nil @folds.add(3, 5)
    assert_equal 2, @folds.size
  end

  def test_at_line_finds_inclusive
    @folds.add(2, 5)
    assert_not_nil @folds.at_line(2)
    assert_not_nil @folds.at_line(5)
    assert_nil @folds.at_line(6)
  end

  def test_hidden_excludes_start_line
    @folds.add(2, 5, closed: true)
    assert_equal false, @folds.hidden?(2)
    assert_equal true, @folds.hidden?(3)
    assert_equal true, @folds.hidden?(5)
    assert_equal false, @folds.hidden?(6)
  end

  def test_hidden_false_when_open
    @folds.add(2, 5, closed: false)
    assert_equal false, @folds.hidden?(3)
  end

  def test_open_close_toggle
    @folds.add(0, 3)
    @folds.open(1)
    assert_equal false, @folds.closed_at?(1)
    @folds.close(1)
    assert_equal true, @folds.closed_at?(1)
    @folds.toggle(1)
    assert_equal false, @folds.closed_at?(1)
  end

  def test_remove
    @folds.add(0, 3)
    @folds.remove(2)
    assert_equal true, @folds.empty?
  end

  def test_clear
    @folds.add(0, 2)
    @folds.add(4, 6)
    @folds.clear
    assert_equal true, @folds.empty?
  end

  def test_open_all_close_all
    @folds.add(0, 2)
    @folds.add(4, 6)
    @folds.open_all
    @folds.each { |f| assert_equal false, f.closed }
    @folds.close_all
    @folds.each { |f| assert_equal true, f.closed }
  end

  def test_shift_after_insert
    @folds.add(5, 10)
    @folds.shift_after(2, +3)
    f = @folds.at_line(8) # original 5, now 8
    assert_not_nil f
    assert_equal 8, f.start_line
    assert_equal 13, f.end_line
  end

  def test_shift_after_delete_drops_intersecting
    @folds.add(5, 10)
    @folds.shift_after(7, -3) # delete lines 7-9
    assert_equal true, @folds.empty?
  end

  def test_shift_after_delete_above_fold
    @folds.add(5, 10)
    @folds.shift_after(0, -2) # delete lines 0-1
    f = @folds.at_line(3)
    assert_not_nil f
    assert_equal 3, f.start_line
    assert_equal 8, f.end_line
  end
end

class TestFoldsFromMarkers < Test::Unit::TestCase
  def test_simple_pair
    buf = ['/* {{{ */', 'body', '/* }}} */']
    assert_equal [[0, 2]], Rvim::Folds.from_markers(buf)
  end

  def test_nested_pairs
    buf = ['{{{', '{{{', 'inner', '}}}', 'outer', '}}}']
    # Inner closes first (LIFO), then outer
    assert_equal [[1, 3], [0, 5]], Rvim::Folds.from_markers(buf)
  end

  def test_unmatched_open_ignored
    buf = ['{{{', 'unclosed', 'more']
    assert_equal [], Rvim::Folds.from_markers(buf)
  end

  def test_unmatched_close_ignored
    buf = ['random', '}}}']
    assert_equal [], Rvim::Folds.from_markers(buf)
  end

  def test_same_line_open_close_ignored_for_zero_width
    buf = ['{{{ }}}']
    # start == end → not added (folding a single line is degenerate; we ship
    # multi-line folds only)
    assert_equal [], Rvim::Folds.from_markers(buf)
  end
end

class TestFoldsFromIndent < Test::Unit::TestCase
  def test_simple_block
    buf = ['def foo', '  body', '  more', 'end']
    assert_equal [[0, 2]], Rvim::Folds.from_indent(buf, 2)
  end

  def test_blank_line_extends_fold
    buf = ['class C', '  body', '', '  more', 'end']
    assert_equal [[0, 3]], Rvim::Folds.from_indent(buf, 2)
  end

  def test_multiple_blocks
    buf = ['def a', '  x', 'end', '', 'def b', '  y', 'end']
    assert_equal [[0, 1], [4, 5]], Rvim::Folds.from_indent(buf, 2)
  end

  def test_no_indent_no_folds
    buf = ['flat', 'flat', 'flat']
    assert_equal [], Rvim::Folds.from_indent(buf, 2)
  end

  def test_zero_shiftwidth_no_op
    assert_equal [], Rvim::Folds.from_indent(['  x'], 0)
  end
end

class TestFoldmethodIndent < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, ['def foo', '  body', '  more', 'end', '', 'def bar', '  thing', 'end'])
  end

  def test_set_foldmethod_indent_creates_folds
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set foldmethod=indent'))
    assert_equal 2, @editor.folds.size
  end
end

class TestFoldLevel < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, ['def foo', '  body', 'end'])
    @editor.folds.add(0, 2, closed: false, level: 1)
  end

  def test_foldlevel_default_99_keeps_open
    @editor.apply_fold_level
    assert_equal false, @editor.folds.at_line(1).closed
  end

  def test_foldlevel_zero_closes_level_1
    @editor.settings.set(:foldlevel, 0)
    @editor.apply_fold_level
    assert_equal true, @editor.folds.at_line(1).closed
  end

  def test_setting_foldlevel_updates_state
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set foldlevel=0'))
    assert_equal true, @editor.folds.at_line(1).closed
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set foldlevel=99'))
    assert_equal false, @editor.folds.at_line(1).closed
  end
end

class TestFoldmethodMarker < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, ['/* {{{ */', 'body', 'more', '/* }}} */', 'tail'])
  end

  def test_set_foldmethod_marker_creates_folds
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set foldmethod=marker'))
    assert_equal 1, @editor.folds.size
    f = @editor.folds.at_line(2)
    assert_not_nil f
    assert_equal 0, f.start_line
    assert_equal 3, f.end_line
  end

  def test_marker_recompute_clears_existing
    @editor.folds.add(0, 1)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set foldmethod=marker'))
    # Existing folds get replaced; we end up with the marker-derived 0..3
    assert_equal 1, @editor.folds.size
    assert_equal 3, @editor.folds.at_line(0).end_line
  end
end

class TestFoldOperationsViaEditor < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, (1..10).map { |i| +"line #{i}" })
    @editor.instance_variable_set(:@line_index, 2)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.config.editing_mode = :vi_command
  end

  def fire_zf(count = 1)
    @editor.send(:rvim_fold_prefix, nil, arg: count)
    proc_ = @editor.instance_variable_get(:@waiting_proc)
    proc_.call('f', nil)
  end

  def fire_z(letter)
    @editor.send(:rvim_fold_prefix, nil, arg: nil)
    proc_ = @editor.instance_variable_get(:@waiting_proc)
    proc_.call(letter, nil)
  end

  def test_zf_with_count_creates_fold
    fire_zf(3)
    f = @editor.folds.at_line(2)
    assert_not_nil f
    assert_equal 2, f.start_line
    assert_equal 4, f.end_line
  end

  def test_zd_removes_fold
    fire_zf(3)
    fire_z('d')
    assert_equal true, @editor.folds.empty?
  end

  def test_zo_zc_toggle
    fire_zf(3)
    fire_z('o')
    assert_equal false, @editor.folds.closed_at?(2)
    fire_z('c')
    assert_equal true, @editor.folds.closed_at?(2)
  end

  def test_za_toggles
    fire_zf(3)
    assert_equal true, @editor.folds.closed_at?(2)
    fire_z('a')
    assert_equal false, @editor.folds.closed_at?(2)
    fire_z('a')
    assert_equal true, @editor.folds.closed_at?(2)
  end

  def test_zE_clears_all
    fire_zf(2)
    @editor.instance_variable_set(:@line_index, 5)
    fire_zf(2)
    fire_z('E')
    assert_equal true, @editor.folds.empty?
  end

  def test_zM_zR_close_open_all
    fire_zf(2)
    @editor.instance_variable_set(:@line_index, 5)
    fire_zf(2)
    fire_z('R')
    @editor.folds.each { |f| assert_equal false, f.closed }
    fire_z('M')
    @editor.folds.each { |f| assert_equal true, f.closed }
  end

  def test_zf_clamps_at_eof
    @editor.instance_variable_set(:@line_index, 8)
    fire_zf(99)
    f = @editor.folds.at_line(8)
    assert_equal 8, f.start_line
    assert_equal 9, f.end_line # buffer has 10 lines (0..9)
  end

  def test_fold_ex_command
    Rvim::Command.execute(@editor, Rvim::Command.parse(':fold 3,5'))
    f = @editor.folds.at_line(3)
    assert_not_nil f
    assert_equal 2, f.start_line # converted from 1-based
    assert_equal 4, f.end_line
  end

  def test_render_skips_hidden_and_shows_placeholder
    @editor.instance_variable_set(:@line_index, 1)
    fire_zf(4) # fold lines 1..4 (0-based)
    # Make a buffer object with the same folds and lines
    buf = FakeBuffer.new(@editor.buffer_of_lines, @editor.folds)
    screen = Rvim::Screen.new(@editor)
    rows = screen.send(:build_display_rows, buf, 0, 10, 80, false)
    # Row 0: line 0
    assert_equal 0, rows[0][0]
    assert_equal false, rows[0][3]
    # Row 1: fold placeholder (line_idx=1, is_fold=true)
    assert_equal 1, rows[1][0]
    assert_equal true, rows[1][3]
    assert_match(/\+-- +4 lines:/, rows[1][2])
    # Row 2: line 5 (lines 2..4 are hidden)
    assert_equal 5, rows[2][0]
    assert_equal false, rows[2][3]
  end

  def test_render_open_fold_shows_all_lines
    @editor.instance_variable_set(:@line_index, 1)
    fire_zf(4)
    fire_z('o') # open the fold
    buf = FakeBuffer.new(@editor.buffer_of_lines, @editor.folds)
    screen = Rvim::Screen.new(@editor)
    rows = screen.send(:build_display_rows, buf, 0, 10, 80, false)
    # All physical lines visible 0..9 (no fold placeholders)
    rows.first(10).each_with_index do |r, i|
      assert_equal i, r[0]
      assert_equal false, r[3]
    end
  end

  def test_j_skips_closed_fold
    @editor.instance_variable_set(:@line_index, 1)
    fire_zf(4) # fold lines 1..4
    @editor.instance_variable_set(:@line_index, 0)
    @editor.send(:ed_next_history, nil) # j
    # j from 0 lands on 1 — fold start, visible
    assert_equal 1, @editor.line_index
    @editor.send(:ed_next_history, nil) # j again
    # Should skip past the closed fold to line 5
    assert_equal 5, @editor.line_index
  end

  def test_k_jumps_to_fold_start
    @editor.instance_variable_set(:@line_index, 1)
    fire_zf(4) # fold 1..4
    @editor.instance_variable_set(:@line_index, 5)
    @editor.send(:ed_prev_history, nil) # k
    # k from 5 should land on fold start (line 1), not 4 which is hidden
    assert_equal 1, @editor.line_index
  end

  def test_G_clamps_to_fold_start_when_target_hidden
    @editor.instance_variable_set(:@line_index, 5)
    fire_zf(4) # fold 5..8
    @editor.instance_variable_set(:@line_index, 0)
    @editor.send(:vi_to_history_line, nil, arg: 7) # G to line 7 (0-based 6)
    # Line 6 is hidden inside fold 5..8 — should snap to start (5)
    assert_equal 5, @editor.line_index
  end

  def test_goto_ex_clamps_to_fold_start
    @editor.instance_variable_set(:@line_index, 5)
    fire_zf(4) # fold 5..8
    @editor.instance_variable_set(:@line_index, 0)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':7'))
    # :7 → 0-based 6, hidden in fold 5..8 → snap to 5
    assert_equal 5, @editor.line_index
  end

  def test_zj_jumps_to_next_fold
    fire_zf(2) # fold lines 2..3
    @editor.instance_variable_set(:@line_index, 5)
    fire_zf(2) # fold lines 5..6
    @editor.instance_variable_set(:@line_index, 0)
    fire_z('j')
    assert_equal 2, @editor.line_index
    fire_z('j')
    assert_equal 5, @editor.line_index
  end

  def test_zk_jumps_to_prev_fold
    fire_zf(2) # 2..3
    @editor.instance_variable_set(:@line_index, 5)
    fire_zf(2) # 5..6
    @editor.instance_variable_set(:@line_index, 9)
    fire_z('k')
    assert_equal 5, @editor.line_index
    fire_z('k')
    assert_equal 2, @editor.line_index
  end

  def test_zn_disables_folding
    @editor.instance_variable_set(:@line_index, 1)
    fire_zf(4)
    fire_z('n')
    assert_equal false, @editor.settings.get(:foldenable)
  end

  def test_zN_enables_folding
    @editor.settings.set(:foldenable, false)
    fire_z('N')
    assert_equal true, @editor.settings.get(:foldenable)
  end

  def test_zi_toggles_folding
    fire_z('i')
    assert_equal false, @editor.settings.get(:foldenable)
    fire_z('i')
    assert_equal true, @editor.settings.get(:foldenable)
  end

  def test_disabling_folding_makes_render_show_all_lines
    @editor.instance_variable_set(:@line_index, 1)
    fire_zf(4) # fold 1..4
    fire_z('n') # disable
    buf = FakeBuffer.new(@editor.buffer_of_lines, @editor.folds)
    screen = Rvim::Screen.new(@editor)
    rows = screen.send(:build_display_rows, buf, 0, 10, 80, false)
    rows.first(10).each_with_index do |r, i|
      assert_equal i, r[0]
      assert_equal false, r[3]
    end
  end

  def test_buffer_swap_preserves_folds
    file_a = Tempfile.new(['a', '.txt'])
    file_a.write((1..10).map { |i| "a#{i}" }.join("\n"))
    file_a.close
    file_b = Tempfile.new(['b', '.txt'])
    file_b.write("b1\nb2\n")
    file_b.close

    @editor.open(file_a.path)
    @editor.instance_variable_set(:@line_index, 2)
    fire_zf(3) # fold lines 2..4 in buffer A

    buf_a = @editor.current_buffer
    @editor.open(file_b.path)
    # Switching buffers should NOT carry buffer A's folds onto B
    assert_equal true, @editor.folds.empty?
    @editor.swap_to_buffer(buf_a)
    refute @editor.folds.empty?, 'expected folds restored on swap back'
    f = @editor.folds.at_line(3)
    assert_not_nil f
  ensure
    file_a&.unlink
    file_b&.unlink
  end
end
