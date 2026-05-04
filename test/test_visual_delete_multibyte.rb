# frozen_string_literal: true

require_relative 'test_helper'

# Regression: visual selection ending on a multibyte char + 'x' (delete)
# would compute the cut boundary as `sel.end_col + 1`, landing inside
# the codepoint. The leftover invalid bytes then crashed the next render
# in mark_trailing_whitespace's regex.
class TestVisualDeleteMultibyte < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'aあい'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.config.editing_mode = :vi_command
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_visual_x_over_japanese_char_leaves_valid_buffer
    send_keys('v', 'l') # select 'a' + 'あ'
    send_keys('x')
    line = @editor.buffer_of_lines[0]
    assert line.valid_encoding?, "buffer line has invalid UTF-8: #{line.bytes.inspect}"
    assert_equal 'い', line
    entry = @editor.read_register('"')
    assert_equal 'aあ', entry.text
  end

  def test_visual_x_full_multibyte_run
    @editor.instance_variable_set(:@buffer_of_lines, [+'あいうえお'])
    @editor.instance_variable_set(:@byte_pointer, 0)
    send_keys('v', 'l', 'l') # select 'あ', 'い', 'う'
    send_keys('x')
    assert_equal 'えお', @editor.buffer_of_lines[0]
    entry = @editor.read_register('"')
    assert_equal 'あいう', entry.text
  end

  def test_visual_x_at_eol_japanese
    send_keys('$', 'v', 'x')
    line = @editor.buffer_of_lines[0]
    assert line.valid_encoding?
    assert_equal 'aあ', line
  end

  def test_end_of_char_at_helper
    line = +'aあい'
    assert_equal 1, Rvim::Selection.end_of_char_at(line, 0) # past 'a'
    assert_equal 4, Rvim::Selection.end_of_char_at(line, 1) # past 'あ'
    assert_equal 7, Rvim::Selection.end_of_char_at(line, 4) # past 'い'
    assert_equal 7, Rvim::Selection.end_of_char_at(line, 7) # already at EOL
  end

  def test_block_delete_with_multibyte_does_not_break
    @editor.instance_variable_set(:@buffer_of_lines, [+'aあb', +'cいd', +'eうf'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 1) # on first multibyte
    send_keys(0x16.chr) # Ctrl-V
    send_keys('j', 'j') # extend down
    send_keys('x')
    @editor.buffer_of_lines.each do |line|
      assert line.valid_encoding?, "line has invalid bytes: #{line.bytes.inspect}"
    end
  end
end
