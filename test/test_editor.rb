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
end
