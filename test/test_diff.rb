# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestDiffAlgorithm < Test::Unit::TestCase
  def test_identical_arrays
    a = %w[alpha beta gamma]
    b = %w[alpha beta gamma]
    a_status, b_status = Rvim::Diff.compute(a, b)
    assert_equal [:common, :common, :common], a_status
    assert_equal [:common, :common, :common], b_status
  end

  def test_completely_different
    a = %w[a b c]
    b = %w[x y z]
    a_status, b_status = Rvim::Diff.compute(a, b)
    assert_equal [:differs, :differs, :differs], a_status
    assert_equal [:differs, :differs, :differs], b_status
  end

  def test_partial_overlap
    a = %w[same1 only_a same2]
    b = %w[same1 same2 only_b]
    a_status, b_status = Rvim::Diff.compute(a, b)
    assert_equal [:common, :differs, :common], a_status
    assert_equal [:common, :common, :differs], b_status
  end

  def test_addition_in_b
    a = %w[a b c]
    b = %w[a inserted b c]
    a_status, b_status = Rvim::Diff.compute(a, b)
    assert_equal [:common, :common, :common], a_status
    assert_equal [:common, :differs, :common, :common], b_status
  end

  def test_deletion_from_a
    a = %w[a b c d]
    b = %w[a c d]
    a_status, b_status = Rvim::Diff.compute(a, b)
    assert_equal [:common, :differs, :common, :common], a_status
    assert_equal [:common, :common, :common], b_status
  end

  def test_empty_arrays
    a_status, b_status = Rvim::Diff.compute([], [])
    assert_equal [], a_status
    assert_equal [], b_status
  end

  def test_one_empty
    a_status, b_status = Rvim::Diff.compute([], %w[x y])
    assert_equal [], a_status
    assert_equal [:differs, :differs], b_status
  end

  def test_hunk_starts
    status = [:common, :differs, :differs, :common, :differs, :common]
    assert_equal [1, 4], Rvim::Diff.hunk_starts(status)
  end

  def test_hunk_starts_at_zero
    status = [:differs, :differs, :common, :differs]
    assert_equal [0, 3], Rvim::Diff.hunk_starts(status)
  end

  def test_hunk_starts_no_diffs
    assert_equal [], Rvim::Diff.hunk_starts([:common, :common])
  end
end

class TestDiffEx < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_diffthis_marks_buffer_active
    file = Tempfile.new(['diff_a', '.txt'])
    file.write("hello\nworld\n")
    file.close
    @editor.open(file.path)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':diffthis'))
    assert_equal true, @editor.current_buffer.diff_active
  ensure
    file&.unlink
  end

  def test_diffsplit_loads_and_marks_both
    file_a = Tempfile.new(['diff_a', '.txt'])
    file_a.write("alpha\nbeta\ngamma\n")
    file_a.close
    file_b = Tempfile.new(['diff_b', '.txt'])
    file_b.write("alpha\nDIFFERENT\ngamma\n")
    file_b.close

    @editor.open(file_a.path)
    Rvim::Command.execute(@editor, Rvim::Command.parse(":diffsplit #{file_b.path}"))
    diff_buffers = @editor.diff_buffers
    assert_equal 2, diff_buffers.size
    diff_buffers.each { |b| assert_not_nil b.diff_status }
  ensure
    file_a&.unlink
    file_b&.unlink
  end

  def test_diffsplit_status_marks_differing_line
    file_a = Tempfile.new(['diff_a', '.txt'])
    file_a.write("alpha\nbeta\ngamma\n")
    file_a.close
    file_b = Tempfile.new(['diff_b', '.txt'])
    file_b.write("alpha\nDIFFERENT\ngamma\n")
    file_b.close

    @editor.open(file_a.path)
    Rvim::Command.execute(@editor, Rvim::Command.parse(":diffsplit #{file_b.path}"))

    a_buf = @editor.buffers.values.find { |b| b.filepath == file_a.path }
    b_buf = @editor.buffers.values.find { |b| b.filepath == file_b.path }
    assert_equal [:common, :differs, :common], a_buf.diff_status
    assert_equal [:common, :differs, :common], b_buf.diff_status
  ensure
    file_a&.unlink
    file_b&.unlink
  end

  def test_diffoff_clears_status
    file = Tempfile.new(['diff', '.txt'])
    file.write("hello\n")
    file.close
    @editor.open(file.path)
    @editor.current_buffer.diff_active = true
    @editor.current_buffer.diff_status = [:common]
    Rvim::Command.execute(@editor, Rvim::Command.parse(':diffoff'))
    assert_equal false, @editor.current_buffer.diff_active
    assert_nil @editor.current_buffer.diff_status
  ensure
    file&.unlink
  end

  def test_bracket_c_jumps_to_diff_hunks
    @editor.instance_variable_set(:@buffer_of_lines, ['a', 'x', 'b', 'y', 'c'])
    buf = Rvim::Buffer.new(1, nil)
    buf.lines = @editor.buffer_of_lines
    buf.diff_status = [:common, :differs, :common, :differs, :common]
    @editor.instance_variable_set(:@current_buffer, buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.diff_jump(:next)
    assert_equal 1, @editor.line_index
    @editor.diff_jump(:next)
    assert_equal 3, @editor.line_index
    @editor.diff_jump(:prev)
    assert_equal 1, @editor.line_index
  end
end
