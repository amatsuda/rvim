# frozen_string_literal: true

require_relative 'test_helper'

# Regression: starting rvim with no filepath should give the user a
# usable [No Name] buffer with a current_window so the cursor lands in
# the main pane (not at the bottom command line). This mirrors vim
# `vim` and nvim `nvim` with no args.
class TestStartupNoFile < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_open_nil_creates_unnamed_buffer
    @editor.open(nil)
    refute_nil @editor.current_buffer
    assert_nil @editor.current_buffer.filepath
  end

  def test_open_nil_sets_current_window
    @editor.open(nil)
    refute_nil @editor.current_window
    assert_same @editor.current_buffer, @editor.current_window.buffer
  end

  def test_open_nil_starts_cursor_at_origin
    @editor.open(nil)
    assert_equal 0, @editor.line_index
    assert_equal 0, @editor.byte_pointer
  end

  def test_open_nil_makes_buffer_of_lines_writable
    @editor.open(nil)
    @editor.insert_at_cursor('hello')
    assert_equal 'hello', @editor.buffer_of_lines[0]
  end

  def test_unnamed_buffer_has_no_name_label
    @editor.open(nil)
    assert_equal '[No Name]', @editor.current_buffer.display_name
  end
end
