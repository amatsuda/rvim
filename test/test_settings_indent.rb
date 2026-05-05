# frozen_string_literal: true

require_relative 'test_helper'

class TestExpandtab < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
    @editor.instance_variable_set(:@buffer_of_lines, [+''])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_default_tab_inserts_literal_tab
    @editor.settings.set(:expandtab, false)
    @editor.send(:rvim_insert_tab, nil)
    assert_equal "\t", @editor.buffer_of_lines[0]
  end

  def test_expandtab_inserts_spaces
    @editor.settings.set(:expandtab, true)
    @editor.settings.set(:shiftwidth, 4)
    @editor.send(:rvim_insert_tab, nil)
    assert_equal '    ', @editor.buffer_of_lines[0]
    assert_equal 4, @editor.byte_pointer
  end

  def test_expandtab_uses_shiftwidth
    @editor.settings.set(:expandtab, true)
    @editor.settings.set(:shiftwidth, 2)
    @editor.send(:rvim_insert_tab, nil)
    assert_equal '  ', @editor.buffer_of_lines[0]
  end

  def test_alias_et_via_set
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set et'))
    assert_equal true, @editor.settings.get(:expandtab)
  end
end

class TestCindentStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:cindent)
  end

  def test_cin_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cin'))
    assert_equal true, @editor.settings.get(:cindent)
  end
end

class TestCinoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:cinoptions)
  end

  def test_cino_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cino=:0,l1,t0,g0'))
    assert_equal ':0,l1,t0,g0', @editor.settings.get(:cinoptions)
  end
end

class TestCinwordsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_keywords
    assert_match(/while/, @editor.settings.get(:cinwords))
  end

  def test_cinw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cinw=if,else'))
    assert_equal 'if,else', @editor.settings.get(:cinwords)
  end
end

class TestLispStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:lisp)
  end

  def test_set_lisp
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lisp'))
    assert_equal true, @editor.settings.get(:lisp)
  end
end

class TestLispwordsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_defun
    assert_match(/defun/, @editor.settings.get(:lispwords))
  end

  def test_lw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lw=defun,defmacro'))
    assert_equal 'defun,defmacro', @editor.settings.get(:lispwords)
  end
end

class TestSofttabstopStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:softtabstop)
  end

  def test_sts_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sts=4'))
    assert_equal 4, @editor.settings.get(:softtabstop)
  end
end

class TestSmarttabStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:smarttab)
  end

  def test_sta_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nosmarttab'))
    assert_equal false, @editor.settings.get(:smarttab)
  end
end

class TestCinkeysStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_braces
    assert_match(/0\{/, @editor.settings.get(:cinkeys))
  end

  def test_cink_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cink=0},0)'))
    assert_equal '0},0)', @editor.settings.get(:cinkeys)
  end
end

class TestIndentexprStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:indentexpr)
  end

  def test_inde_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set inde=GetRubyIndent()'))
    assert_equal 'GetRubyIndent()', @editor.settings.get(:indentexpr)
  end
end

class TestIndentkeysStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_braces
    assert_match(/0\}/, @editor.settings.get(:indentkeys))
  end

  def test_indk_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set indk=0=,0)'))
    assert_equal '0=,0)', @editor.settings.get(:indentkeys)
  end
end

class TestCinscopedeclsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_public_etc
    assert_match(/public/, @editor.settings.get(:cinscopedecls))
  end

  def test_cinsd_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cinsd=public'))
    assert_equal 'public', @editor.settings.get(:cinscopedecls)
  end
end

class TestLispoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:lispoptions)
  end

  def test_lop_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lop=expr:1'))
    assert_equal 'expr:1', @editor.settings.get(:lispoptions)
  end
end

class TestAutoindent < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def test_default_no_indent_carry
    @editor.instance_variable_set(:@buffer_of_lines, [+'    hello world'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 9) # after 'hello'
    @editor.send(:rvim_insert_newline, nil)
    assert_equal ['    hello', ' world'], @editor.buffer_of_lines
  end

  def test_autoindent_carries_leading_whitespace
    @editor.settings.set(:autoindent, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+'    hello world'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 9) # after 'hello'
    @editor.send(:rvim_insert_newline, nil)
    assert_equal ['    hello', '     world'], @editor.buffer_of_lines
    # Cursor lands at end of indent on new line
    assert_equal 1, @editor.line_index
    assert_equal 4, @editor.byte_pointer
  end

  def test_autoindent_with_tabs
    @editor.settings.set(:autoindent, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+"\t\thello"])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 7)
    @editor.send(:rvim_insert_newline, nil)
    assert_equal "\t\t", @editor.buffer_of_lines[1].byteslice(0, 2)
  end

  def test_ai_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ai'))
    assert_equal true, @editor.settings.get(:autoindent)
  end
end

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
