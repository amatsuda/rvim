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

  def test_add_rejects_overlap
    @folds.add(0, 4)
    assert_nil @folds.add(2, 6)
    assert_equal 1, @folds.size
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
