# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestEditor < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def feed(char, sym = nil)
    @editor.update(Reline::Key.new(char, sym, false))
  end

  def test_open_loads_lines
    Tempfile.create('rvim_open') do |tf|
      tf.write("foo\nbar\nbaz\n")
      tf.flush
      @editor.open(tf.path)
      assert_equal %w[foo bar baz], @editor.buffer_of_lines
      assert_equal tf.path, @editor.filepath
      assert_equal 0, @editor.line_index
      assert_equal 0, @editor.byte_pointer
    end
  end

  def test_open_missing_file_creates_empty_buffer
    @editor.open('/no/such/path/here.txt')
    assert_equal [''], @editor.buffer_of_lines
  end

  def test_save_writes_to_disk
    Tempfile.create('rvim_save') do |tf|
      tf.close
      @editor.instance_variable_set(:@buffer_of_lines, %w[one two three])
      @editor.instance_variable_set(:@filepath, tf.path)
      @editor.save
      assert_equal "one\ntwo\nthree\n", File.read(tf.path)
      assert_equal false, @editor.modified
    end
  end

  def test_j_navigates_within_buffer_no_history_fallthrough
    @editor.instance_variable_set(:@buffer_of_lines, %w[a b c])
    feed('j', :ed_next_history)
    feed('j', :ed_next_history)
    assert_equal 2, @editor.line_index
    feed('j', :ed_next_history) # capped at last
    assert_equal 2, @editor.line_index
  end

  def test_k_navigates_up_capped_at_zero
    @editor.instance_variable_set(:@buffer_of_lines, %w[a b c])
    @editor.instance_variable_set(:@line_index, 2)
    feed('k', :ed_prev_history)
    feed('k', :ed_prev_history)
    feed('k', :ed_prev_history) # capped
    assert_equal 0, @editor.line_index
  end

  def test_gg_jumps_to_first_line
    @editor.instance_variable_set(:@buffer_of_lines, %w[a b c d])
    @editor.instance_variable_set(:@line_index, 3)
    feed('g', :rvim_g_prefix)
    feed('g', nil)
    assert_equal 0, @editor.line_index
  end

  def test_count_gg_jumps_to_that_line
    @editor.instance_variable_set(:@buffer_of_lines, ('a'..'z').to_a)
    @editor.instance_variable_set(:@line_index, 0)
    # [count]gg = jump to line [count] (1-based). 3gg → line 3 → index 2.
    @editor.send(:rvim_g_prefix, Reline::Key.new('g', :rvim_g_prefix, false), arg: 3)
    feed('g', nil)
    assert_equal 2, @editor.line_index
  end

  def test_count_gg_clamps_past_end
    @editor.instance_variable_set(:@buffer_of_lines, %w[a b c d])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.send(:rvim_g_prefix, Reline::Key.new('g', :rvim_g_prefix, false), arg: 999)
    feed('g', nil)
    assert_equal 3, @editor.line_index # clamped to last line index
  end

  def test_capital_G_jumps_to_last_line
    @editor.instance_variable_set(:@buffer_of_lines, %w[a b c d])
    feed('G', :vi_to_history_line)
    assert_equal 3, @editor.line_index
  end

  def test_o_opens_line_below_and_enters_insert_mode
    @editor.instance_variable_set(:@buffer_of_lines, %w[alpha beta])
    feed('o', :rvim_open_below)
    assert_equal 3, @editor.buffer_of_lines.size
    assert_equal 1, @editor.line_index
    assert_equal '', @editor.buffer_of_lines[1]
    assert_equal :vi_insert, @editor.editing_mode_label
  end

  def test_capital_O_opens_line_above
    @editor.instance_variable_set(:@buffer_of_lines, %w[alpha beta])
    @editor.instance_variable_set(:@line_index, 1)
    feed('O', :rvim_open_above)
    assert_equal 3, @editor.buffer_of_lines.size
    assert_equal 1, @editor.line_index
    assert_equal '', @editor.buffer_of_lines[1]
    assert_equal :vi_insert, @editor.editing_mode_label
  end

  def test_modified_flag_set_after_edit
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    feed('i', :vi_insert)
    feed('X', :ed_insert)
    assert_equal true, @editor.modified
  end

  def test_modified_flag_cleared_after_save
    Tempfile.create('rvim_mod') do |tf|
      tf.close
      @editor.instance_variable_set(:@buffer_of_lines, [+'hi'])
      @editor.instance_variable_set(:@filepath, tf.path)
      @editor.modified = true
      @editor.save
      assert_equal false, @editor.modified
    end
  end

  def test_v_enters_visual_char_mode
    @editor.instance_variable_set(:@buffer_of_lines, %w[alpha beta])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
    feed('v', :rvim_visual_char)
    assert_equal :char, @editor.visual_mode
    assert_equal [0, 2], @editor.visual_anchor
  end

  def test_capital_V_enters_visual_line_mode
    @editor.instance_variable_set(:@buffer_of_lines, %w[a b c])
    feed('V', :rvim_visual_line)
    assert_equal :line, @editor.visual_mode
  end

  def test_esc_exits_visual_and_stashes_last_visual
    @editor.instance_variable_set(:@buffer_of_lines, %w[a b c])
    feed('v', :rvim_visual_char)
    feed("\e", nil)
    assert_nil @editor.visual_mode
    last = @editor.instance_variable_get(:@last_visual)
    assert_equal :char, last[:mode]
  end

  def test_v_in_visual_char_exits
    @editor.instance_variable_set(:@buffer_of_lines, %w[a b c])
    feed('v', :rvim_visual_char)
    feed('v', :rvim_visual_char)
    assert_nil @editor.visual_mode
  end

  def test_V_in_visual_char_switches_to_line
    @editor.instance_variable_set(:@buffer_of_lines, %w[a b c])
    feed('v', :rvim_visual_char)
    feed('V', :rvim_visual_line)
    assert_equal :line, @editor.visual_mode
  end

  def test_selection_returns_nil_when_not_in_visual
    assert_nil @editor.selection
  end

  def test_selection_returns_object_in_visual
    @editor.instance_variable_set(:@buffer_of_lines, %w[alpha beta])
    feed('v', :rvim_visual_char)
    assert_kind_of Rvim::Selection, @editor.selection
  end

  def test_change_recording_freezes_on_modification
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    feed('i', :vi_insert)
    feed('X', :ed_insert)
    feed("\e", :vi_command_mode)
    assert @editor.last_change_keys.size >= 3, 'expected i X Esc to be recorded'
  end

  def test_pure_motion_does_not_record_change
    @editor.instance_variable_set(:@buffer_of_lines, %w[alpha beta gamma])
    feed('j', :ed_next_history)
    feed('j', :ed_next_history)
    assert_equal [], @editor.last_change_keys
  end

  def test_dw_records_two_keys
    @editor.instance_variable_set(:@buffer_of_lines, [+'foo bar baz'])
    feed('d', :vi_delete_meta)
    feed('w', :vi_next_word)
    assert_equal 2, @editor.last_change_keys.size
  end
end
