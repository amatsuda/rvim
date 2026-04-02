# frozen_string_literal: true

require_relative 'test_helper'

class TestCompletionWordCollection < Test::Unit::TestCase
  def test_candidates_collects_unique_words
    lines = ['hello world', 'world peace', 'hello again']
    assert_equal %w[again hello peace world], Rvim::Completion.candidates(lines, '')
  end

  def test_candidates_filters_by_prefix
    lines = ['hello help hero hi']
    assert_equal %w[hello help hero], Rvim::Completion.candidates(lines, 'he')
  end

  def test_candidates_drops_bare_base
    lines = ['hello hello world']
    assert_equal %w[hello world], Rvim::Completion.candidates(lines, '')
    # base = 'hello' is dropped from the candidate set even though it appears
    assert_equal [], Rvim::Completion.candidates(lines, 'hello')
  end

  def test_candidates_empty_when_no_match
    lines = ['foo bar baz']
    assert_equal [], Rvim::Completion.candidates(lines, 'qux')
  end

  def test_base_at_walks_word_chars_left
    assert_equal 'hel', Rvim::Completion.base_at('hello world', 3)
    assert_equal 'hello', Rvim::Completion.base_at('hello world', 5)
    assert_equal '', Rvim::Completion.base_at('hello world', 6)
    assert_equal 'world', Rvim::Completion.base_at('hello world', 11)
  end

  def test_base_at_handles_empty_line
    assert_equal '', Rvim::Completion.base_at('', 0)
    assert_equal '', Rvim::Completion.base_at(nil, 0)
  end

  def test_base_start
    assert_equal 0, Rvim::Completion.base_start('hello', 3)
    assert_equal 6, Rvim::Completion.base_start('hello world', 11)
  end
end

class TestCompletionDispatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def buf(*lines, line: 0, byte: 0)
    @editor.instance_variable_set(:@buffer_of_lines, lines.map { |l| +l })
    @editor.instance_variable_set(:@line_index, line)
    @editor.instance_variable_set(:@byte_pointer, byte)
  end

  def k(ch, sym = nil)
    Reline::Key.new(ch, sym, false)
  end

  def ctrl_n
    @editor.update(k("\x0E", :rvim_complete_next))
  end

  def ctrl_p
    @editor.update(k("\x10", :rvim_complete_prev))
  end

  def test_ctrl_n_replaces_partial_with_first_match
    buf('hello world hero help', 'he', line: 1, byte: 2)
    ctrl_n
    # candidates filtered by 'he' from all lines: hello, help, hero (sorted)
    assert_equal 'hello', @editor.buffer_of_lines[1]
    assert_equal 5, @editor.byte_pointer
    assert_equal true, @editor.completion_active
  end

  def test_ctrl_n_cycles_forward
    buf('hello hero help', 'he', line: 1, byte: 2)
    ctrl_n
    assert_equal 'hello', @editor.buffer_of_lines[1]
    ctrl_n
    assert_equal 'help', @editor.buffer_of_lines[1]
    ctrl_n
    assert_equal 'hero', @editor.buffer_of_lines[1]
    ctrl_n # wraps
    assert_equal 'hello', @editor.buffer_of_lines[1]
  end

  def test_ctrl_p_cycles_backward
    buf('hello hero help', 'he', line: 1, byte: 2)
    ctrl_p
    # First Ctrl-P starts at last candidate (alphabetical: hello, help, hero)
    assert_equal 'hero', @editor.buffer_of_lines[1]
    ctrl_p
    assert_equal 'help', @editor.buffer_of_lines[1]
  end

  def test_ctrl_n_no_matches_sets_status
    buf('hello world', 'qux', line: 1, byte: 3)
    ctrl_n
    assert_equal 'Pattern not found', @editor.status_message
    assert_equal 'qux', @editor.buffer_of_lines[1]
    assert_equal false, @editor.completion_active
  end

  def test_status_shows_match_position
    buf('hello hero help', 'he', line: 1, byte: 2)
    ctrl_n
    assert_match(/match 1 of 3: hello/, @editor.status_message.to_s)
    ctrl_n
    assert_match(/match 2 of 3: help/, @editor.status_message.to_s)
  end

  def test_typing_other_char_cancels_completion
    buf('hello hero', 'he', line: 1, byte: 2)
    ctrl_n
    assert_equal true, @editor.completion_active
    # Send a plain char with method_symbol=:ed_insert so super.update dispatches
    sym = @editor.send(:synthesize_key, 'x').method_symbol
    @editor.update(k('x', sym))
    assert_equal false, @editor.completion_active
  end

  def test_ctrl_n_preserves_text_after_cursor
    # Use a non-word separator '-' so scan splits "he-suffix" into "he", "suffix".
    # Then the bare base "he" is dropped, leaving "hello" and "suffix" as candidates.
    buf('hello world', 'he-suffix', line: 1, byte: 2)
    ctrl_n
    # base = "he" → replaced by first match "hello"; tail "-suffix" preserved.
    assert_equal 'hello-suffix', @editor.buffer_of_lines[1]
  end

  def test_empty_base_lists_all_words
    buf('alpha beta gamma', '', line: 1, byte: 0)
    ctrl_n
    assert_equal 'alpha', @editor.buffer_of_lines[1]
  end

  def test_replacement_marks_modified
    buf('hello hero', 'he', line: 1, byte: 2)
    @editor.modified = false
    ctrl_n
    assert_equal true, @editor.modified
  end
end
