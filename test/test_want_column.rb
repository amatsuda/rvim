# frozen_string_literal: true

require_relative 'test_helper'

# Vim's "curswant": vertical motions (j/k, arrow up/down) remember
# the column the user *wanted* to be on. When a short target line
# clamps the cursor, returning to a longer line restores the wanted
# column — `abcd` ↓ `ef` ↑ lands back on `d`, not `b`.
#
# Any horizontal motion in between invalidates curswant: the next
# vertical move snapshots wherever the user currently is.

class TestWantColumn < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'abcd', +'ef', +'ghijk'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 3) # on 'd'
    @editor.config.editing_mode = :vi_command
  end

  def test_down_then_up_restores_original_column
    @editor.send(:rvim_arrow_down, nil)
    assert_equal 1, @editor.line_index
    assert_equal 1, @editor.byte_pointer # clamped onto 'f'

    @editor.send(:rvim_arrow_up, nil)
    assert_equal 0, @editor.line_index
    assert_equal 3, @editor.byte_pointer, 'restored onto `d`'
  end

  def test_two_downs_recover_full_column_on_longer_line
    # abcd → ef (clamp 1) → ghijk (should be col 3 again)
    @editor.send(:rvim_arrow_down, nil)
    @editor.send(:rvim_arrow_down, nil)
    assert_equal 2, @editor.line_index
    assert_equal 3, @editor.byte_pointer, 'curswant restored on ghijk'
  end

  def test_horizontal_motion_invalidates_curswant
    @editor.send(:rvim_arrow_down, nil) # ef, col 1
    @editor.send(:rvim_arrow_left, nil) # col 0 (horizontal!)
    @editor.send(:rvim_arrow_up, nil)   # abcd
    assert_equal 0, @editor.byte_pointer, 'curswant was invalidated by ←'
  end

  def test_horizontal_motion_then_vertical_uses_new_column
    @editor.send(:rvim_arrow_down, nil) # ef, col 1
    @editor.send(:rvim_arrow_left, nil) # ef, col 0
    @editor.send(:rvim_arrow_down, nil) # ghijk: new curswant=0, lands at 0
    assert_equal 0, @editor.byte_pointer
  end

  def test_repeated_down_does_not_overwrite_want_column
    # Even when the target line is shorter, subsequent downs keep
    # heading toward the original column.
    @editor.instance_variable_set(:@buffer_of_lines, [+'abcdef', +'a', +'b', +'cdefgh'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 5) # on 'f'
    @editor.send(:rvim_arrow_down, nil) # 'a' line, clamped
    @editor.send(:rvim_arrow_down, nil) # 'b' line, clamped
    @editor.send(:rvim_arrow_down, nil) # cdefgh: should restore col 5
    assert_equal 5, @editor.byte_pointer
  end

  def test_works_with_j_k_too
    # ed_prev_history / ed_next_history (Reline's symbols for j/k)
    # use the same want_column machinery so the UX is consistent.
    @editor.send(:ed_next_history, nil) # ef
    assert_equal 1, @editor.byte_pointer
    @editor.send(:ed_prev_history, nil) # abcd
    assert_equal 3, @editor.byte_pointer
  end

  def test_vertical_motion_snaps_back_to_char_start_for_multibyte
    # Cursor at col 2 (on `c`) of `abcd`, then UP onto a line whose
    # col 2 lands inside a multibyte `あ`. The byte_pointer must snap
    # back to byte 1 (start of `あ`) — otherwise Reline's width / regex
    # code crashes on the invalid UTF-8 continuation byte.
    @editor.instance_variable_set(:@buffer_of_lines, [+'xあy', +'abcd'])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2) # on 'c'
    @editor.send(:rvim_arrow_up, nil)
    assert_equal 0, @editor.line_index
    assert_equal 1, @editor.byte_pointer, 'snapped back to start of あ'
  end
end
