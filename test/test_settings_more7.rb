# frozen_string_literal: true

require_relative 'test_helper'

class TestSmartindent < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
    @editor.settings.set(:smartindent, true)
    @editor.settings.set(:shiftwidth, 2)
  end

  def insert_at(line, col)
    @editor.instance_variable_set(:@buffer_of_lines, [+line])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, col)
    @editor.send(:rvim_insert_newline, nil)
  end

  def test_open_brace_increases_indent
    insert_at('def foo() {', 11)
    assert_equal ['def foo() {', '  '], @editor.buffer_of_lines
    assert_equal 2, @editor.byte_pointer
  end

  def test_close_brace_dedents
    @editor.instance_variable_set(:@buffer_of_lines, [+'  body', +'  }'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 6)
    @editor.send(:rvim_insert_newline, nil)
    # head = '  body', tail = '', new line gets '  ' indent
    assert_equal '  ', @editor.buffer_of_lines[1]
  end

  def test_open_brace_with_close_in_tail_dedents_back
    # Simulating cursor between { and } on same line: 'function() {|}'
    insert_at('function() {}', 12)
    # head = 'function() {', tail = '}', smartindent gives indent=base+sw, then dedents because tail starts with }
    # base indent = '', +sw = '  ', then dedent sw → ''
    assert_equal ['function() {', '}'], @editor.buffer_of_lines
  end

  def test_no_smartindent_off
    @editor.settings.set(:smartindent, false)
    @editor.settings.set(:autoindent, false)
    insert_at('def foo() {', 11)
    assert_equal ['def foo() {', ''], @editor.buffer_of_lines
  end

  def test_si_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set si'))
    assert_equal true, @editor.settings.get(:smartindent)
  end
end

class TestStartofline < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, ['top', '    indented line', '  middle', 'bottom'])
  end

  def fire_g(letter)
    @editor.send(:rvim_g_prefix, nil, arg: nil)
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
  end

  def test_default_sol_jumps_to_first_nonblank
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 5)
    fire_g('g')
    assert_equal 0, @editor.line_index
    assert_equal 0, @editor.byte_pointer # 'top' starts at col 0
  end

  def test_gg_to_indented_line_lands_on_first_nonblank
    # We need an indented first line for the difference to show
    @editor.instance_variable_set(:@buffer_of_lines, ['  start', 'middle', 'end'])
    @editor.instance_variable_set(:@line_index, 2)
    fire_g('g')
    assert_equal 2, @editor.byte_pointer # past 2 spaces
  end

  def test_sol_off_keeps_cursor_at_zero
    @editor.settings.set(:startofline, false)
    @editor.instance_variable_set(:@buffer_of_lines, ['  start', 'middle'])
    @editor.instance_variable_set(:@line_index, 1)
    fire_g('g')
    assert_equal 0, @editor.byte_pointer
  end

  def test_G_lands_on_first_nonblank
    @editor.instance_variable_set(:@buffer_of_lines, ['top', '  bottom'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.send(:vi_to_history_line, nil, arg: nil)
    assert_equal 1, @editor.line_index
    assert_equal 2, @editor.byte_pointer
  end

  def test_sol_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nosol'))
    assert_equal false, @editor.settings.get(:startofline)
  end
end

class TestKeywordprg < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def test_default_is_man
    assert_equal 'man', @editor.settings.get(:keywordprg)
  end

  def test_kp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set kp=help'))
    assert_equal 'help', @editor.settings.get(:keywordprg)
  end

  def test_K_uses_keywordprg
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello world'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    # Use 'echo' as keywordprg so it always succeeds and is portable
    @editor.settings.set(:keywordprg, 'echo')
    @editor.send(:rvim_keyword_lookup, nil)
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/hello/, body)
  end

  def test_K_with_no_word_sets_status
    @editor.instance_variable_set(:@buffer_of_lines, [+'   '])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:rvim_keyword_lookup, nil)
    assert_match(/E348/, @editor.status_message.to_s)
  end

  def test_K_with_failing_program
    @editor.instance_variable_set(:@buffer_of_lines, [+'word'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.settings.set(:keywordprg, 'false')
    @editor.send(:rvim_keyword_lookup, nil)
    assert_match(/^K:/, @editor.status_message.to_s)
  end
end
