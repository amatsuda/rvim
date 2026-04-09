# frozen_string_literal: true

require_relative 'test_helper'

class TestReformatModule < Test::Unit::TestCase
  def test_wrap_short_paragraph
    out = Rvim::Reformat.wrap(['hello world how are you doing'], 12)
    assert_equal ['hello world', 'how are you', 'doing'], out
  end

  def test_wrap_preserves_blank_separator
    lines = ['a b c', '', 'd e f']
    out = Rvim::Reformat.wrap(lines, 5)
    assert_equal ['a b c', '', 'd e f'], out
  end

  def test_wrap_collapses_multi_line_paragraph
    lines = ['hello', 'world', 'how are', 'you']
    out = Rvim::Reformat.wrap(lines, 80)
    assert_equal ['hello world how are you'], out
  end

  def test_wrap_zero_width_no_op
    assert_equal ['x'], Rvim::Reformat.wrap(['x'], 0)
  end
end

class TestGqOperator < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
    @editor.settings.set(:textwidth, 12)
  end

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def fire_g(letter)
    @editor.send(:rvim_g_prefix, nil, arg: nil)
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
  end

  def test_gqq_reformats_current_line
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello world how are you doing'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    fire_g('q')
    @editor.update(k('q'))
    assert_equal ['hello world', 'how are you', 'doing'], @editor.buffer_of_lines
  end

  def test_gqj_reformats_two_lines
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello', +'world how are', +'tail'])
    @editor.instance_variable_set(:@line_index, 0)
    fire_g('q')
    @editor.update(k('j'))
    # gq + j → motion to line 1, reformat lines 0..1
    assert @editor.buffer_of_lines[0..1].join.include?('hello')
    assert_equal 'tail', @editor.buffer_of_lines.last
  end
end

class TestFilterMotion < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def test_double_bang_starts_filter_for_current_line
    @editor.instance_variable_set(:@buffer_of_lines, [+'one', +'two', +'three'])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.send(:rvim_filter_operator, nil)
    @editor.update(k('!'))
    assert_equal :ex, @editor.prompt_mode
    assert_equal '2,2!', @editor.prompt_buffer
  end

  def test_bang_with_motion_starts_filter_for_range
    @editor.instance_variable_set(:@buffer_of_lines, [+'one', +'two', +'three', +'four'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.send(:rvim_filter_operator, nil)
    @editor.update(k('j'))
    assert_equal :ex, @editor.prompt_mode
    assert_equal '1,2!', @editor.prompt_buffer
  end

  def test_visual_bang_uses_selection
    @editor.instance_variable_set(:@buffer_of_lines, [+'a', +'b', +'c', +'d'])
    @editor.instance_variable_set(:@visual_mode, :line)
    @editor.instance_variable_set(:@visual_anchor, [1, 0])
    @editor.instance_variable_set(:@line_index, 2)
    @editor.update(k('!'))
    assert_equal :ex, @editor.prompt_mode
    assert_match(/\A2,3!/, @editor.prompt_buffer)
  end
end

class TestOperatorOnSearchMatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def test_operator_on_next_search_match_deletes_match
    @editor.instance_variable_set(:@buffer_of_lines, [+'foo bar foo'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    pattern = 'foo'
    matches = Rvim::Search.scan(@editor.buffer_of_lines, pattern)
    @editor.instance_variable_set(:@search_pattern, pattern)
    @editor.instance_variable_set(:@search_matches, matches)
    @editor.instance_variable_set(:@vi_waiting_operator, :vi_delete_meta_confirm)
    @editor.select_next_search_match(:forward)
    # next_match advances past the cursor, picking the second 'foo' (byte 8..10)
    assert_equal 'foo bar ', @editor.buffer_of_lines[0]
  end

  def test_yank_on_next_search_match
    @editor.instance_variable_set(:@buffer_of_lines, [+'foo bar foo'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 4)
    pattern = 'foo'
    matches = Rvim::Search.scan(@editor.buffer_of_lines, pattern)
    @editor.instance_variable_set(:@search_pattern, pattern)
    @editor.instance_variable_set(:@search_matches, matches)
    @editor.instance_variable_set(:@vi_waiting_operator, :vi_yank_confirm)
    @editor.select_next_search_match(:forward)
    entry = @editor.read_register('"')
    assert_equal 'foo', entry.text
    assert_equal 'foo bar foo', @editor.buffer_of_lines[0] # not modified
  end
end
