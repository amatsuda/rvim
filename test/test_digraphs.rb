# frozen_string_literal: true

require_relative 'test_helper'

class TestDigraphsTable < Test::Unit::TestCase
  def setup
    Rvim::Digraphs.reset!
  end

  def teardown
    Rvim::Digraphs.reset!
  end

  def test_default_lookups
    assert_equal 'œ', Rvim::Digraphs.lookup('oe')
    assert_equal 'Œ', Rvim::Digraphs.lookup('OE')
    assert_equal '€', Rvim::Digraphs.lookup('Eu')
    assert_equal '→', Rvim::Digraphs.lookup('->')
    assert_equal '≤', Rvim::Digraphs.lookup('<=')
    assert_equal '♥', Rvim::Digraphs.lookup('<3')
  end

  def test_unknown_pair_returns_nil
    assert_nil Rvim::Digraphs.lookup('zz')
    assert_nil Rvim::Digraphs.lookup('')
    assert_nil Rvim::Digraphs.lookup('x')
    assert_nil Rvim::Digraphs.lookup('xyz')
  end

  def test_define_with_codepoint
    Rvim::Digraphs.define('xy', 0x2603)
    assert_equal '☃', Rvim::Digraphs.lookup('xy')
  end

  def test_define_with_string
    Rvim::Digraphs.define('xz', 'WAT')
    assert_equal 'WAT', Rvim::Digraphs.lookup('xz')
  end

  def test_user_overrides_default
    Rvim::Digraphs.define('oe', 0x2603)
    assert_equal '☃', Rvim::Digraphs.lookup('oe')
  end

  def test_size_includes_user_table
    base = Rvim::Digraphs.size
    Rvim::Digraphs.define('xy', 0x2603)
    assert_equal base + 1, Rvim::Digraphs.size
  end
end

class TestDigraphsExCommand < Test::Unit::TestCase
  def setup
    Rvim::Digraphs.reset!
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def teardown
    Rvim::Digraphs.reset!
  end

  def test_no_args_lists_table
    Rvim::Command.execute(@editor, Rvim::Command.parse(':digraphs'))
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/oe/, body)
    assert_match(/œ/, body)
  end

  def test_define_via_command
    Rvim::Command.execute(@editor, Rvim::Command.parse(':digraph xy 9731'))
    assert_equal '☃', Rvim::Digraphs.lookup('xy')
  end

  def test_invalid_codepoint_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':digraph xy zero'))
    assert_match(/E471/, @editor.status_message.to_s)
  end

  def test_missing_args_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':digraph xy'))
    assert_match(/E471/, @editor.status_message.to_s)
  end
end

class TestDigraphsDispatch < Test::Unit::TestCase
  def setup
    Rvim::Digraphs.reset!
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
    @editor.instance_variable_set(:@buffer_of_lines, [+''])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def teardown
    Rvim::Digraphs.reset!
  end

  def k(ch, sym = nil)
    Reline::Key.new(ch, sym, false)
  end

  def fire_ctrl_k
    @editor.send(:rvim_digraph_start, nil)
  end

  def test_ctrl_k_then_oe_inserts_digraph
    fire_ctrl_k
    @editor.update(k('o'))
    @editor.update(k('e'))
    assert_equal 'œ', @editor.buffer_of_lines[0]
    assert_equal 'œ'.bytesize, @editor.byte_pointer
  end

  def test_ctrl_k_then_arrow
    fire_ctrl_k
    @editor.update(k('-'))
    @editor.update(k('>'))
    assert_equal '→', @editor.buffer_of_lines[0]
  end

  def test_unknown_pair_sets_status
    fire_ctrl_k
    @editor.update(k('z'))
    @editor.update(k('z'))
    assert_match(/E1050/, @editor.status_message.to_s)
    assert_equal '', @editor.buffer_of_lines[0]
  end

  def test_state_clears_after_digraph
    fire_ctrl_k
    @editor.update(k('o'))
    @editor.update(k('e'))
    assert_equal false, @editor.instance_variable_get(:@digraph_pending)
    assert_equal '', @editor.instance_variable_get(:@digraph_chars)
  end

  def test_inserts_at_cursor_position
    @editor.instance_variable_set(:@buffer_of_lines, [+'abc'])
    @editor.instance_variable_set(:@byte_pointer, 1)
    fire_ctrl_k
    @editor.update(k('o'))
    @editor.update(k('e'))
    assert_equal 'aœbc', @editor.buffer_of_lines[0]
  end

  def test_marks_buffer_modified
    @editor.modified = false
    fire_ctrl_k
    @editor.update(k('o'))
    @editor.update(k('e'))
    assert_equal true, @editor.modified
  end
end
