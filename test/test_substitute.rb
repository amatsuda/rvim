# frozen_string_literal: true

require_relative 'test_helper'

class TestSubstituteChar < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 1)
    @editor.config.editing_mode = :vi_command
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_s_deletes_one_char_and_enters_insert
    send_keys('s')
    assert_equal 'hllo', @editor.buffer_of_lines[0]
    assert_equal :vi_insert, @editor.editing_mode_label
    assert_equal 1, @editor.byte_pointer
  end

  def test_s_yanks_deleted_to_unnamed_register
    send_keys('s')
    entry = @editor.read_register('"')
    refute_nil entry
    assert_equal 'e', entry.text
  end

  def test_s_at_eol_does_nothing_in_buffer
    @editor.instance_variable_set(:@byte_pointer, 5) # past 'o'
    send_keys('s')
    assert_equal 'hello', @editor.buffer_of_lines[0]
    assert_equal :vi_insert, @editor.editing_mode_label
  end

  def test_then_typed_chars_replace
    send_keys('s')
    @editor.insert_at_cursor('XYZ')
    assert_equal 'hXYZllo', @editor.buffer_of_lines[0]
  end
end

class TestSubstituteLine < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'  indented', +'second', +'third'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 4)
    @editor.config.editing_mode = :vi_command
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_S_blanks_current_line_and_enters_insert
    send_keys('S')
    assert_equal '', @editor.buffer_of_lines[0]
    assert_equal 'second', @editor.buffer_of_lines[1]
    assert_equal :vi_insert, @editor.editing_mode_label
    assert_equal 0, @editor.byte_pointer
  end

  def test_S_yanks_full_line_to_unnamed_register
    send_keys('S')
    entry = @editor.read_register('"')
    refute_nil entry
    assert_equal '  indented', entry.text
    assert_equal :line, entry.kind
  end

  def test_then_type_replaces_blanked_line
    send_keys('S')
    @editor.insert_at_cursor('NEW')
    assert_equal 'NEW', @editor.buffer_of_lines[0]
  end
end
