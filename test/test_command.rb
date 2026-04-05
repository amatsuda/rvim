# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestCommand < Test::Unit::TestCase
  def test_parse_w
    parsed = Rvim::Command.parse(':w')
    assert_equal :w, parsed.verb
    assert_nil parsed.arg
    assert_equal false, parsed.bang
  end

  def test_parse_w_with_path
    parsed = Rvim::Command.parse(':w foo.txt')
    assert_equal :w, parsed.verb
    assert_equal 'foo.txt', parsed.arg
  end

  def test_parse_q_bang
    parsed = Rvim::Command.parse(':q!')
    assert_equal :q, parsed.verb
    assert_equal true, parsed.bang
  end

  def test_parse_wq_and_x
    assert_equal :wq, Rvim::Command.parse(':wq').verb
    assert_equal :wq, Rvim::Command.parse(':x').verb
  end

  def test_parse_e_with_path
    parsed = Rvim::Command.parse(':e other.rb')
    assert_equal :e, parsed.verb
    assert_equal 'other.rb', parsed.arg
  end

  def test_parse_line_number
    parsed = Rvim::Command.parse(':42')
    assert_equal :goto, parsed.verb
    assert_equal 42, parsed.line_number
  end

  def test_parse_empty
    assert_nil Rvim::Command.parse(':')
    assert_nil Rvim::Command.parse('')
  end

  def test_execute_write_creates_file
    Tempfile.create('rvim_test') do |tf|
      path = tf.path
      tf.close
      File.unlink(path)

      editor = Rvim::Editor.new(Reline.core.config)
      editor.instance_variable_set(:@buffer_of_lines, %w[hello world])
      editor.instance_variable_set(:@filepath, path)

      Rvim::Command.execute(editor, Rvim::Command.parse(':w'))
      assert_equal "hello\nworld\n", File.read(path)
    end
  end

  def test_execute_quit_blocks_when_modified
    editor = Rvim::Editor.new(Reline.core.config)
    editor.modified = true
    Rvim::Command.execute(editor, Rvim::Command.parse(':q'))
    assert_equal false, editor.quit?
    assert_match(/E37/, editor.status_message)
  end

  def test_execute_quit_bang_overrides
    editor = Rvim::Editor.new(Reline.core.config)
    editor.modified = true
    Rvim::Command.execute(editor, Rvim::Command.parse(':q!'))
    assert_equal true, editor.quit?
  end

  def test_execute_goto
    editor = Rvim::Editor.new(Reline.core.config)
    editor.instance_variable_set(:@buffer_of_lines, (1..10).map(&:to_s))
    Rvim::Command.execute(editor, Rvim::Command.parse(':5'))
    assert_equal 4, editor.line_index
  end

  def test_execute_goto_clamps
    editor = Rvim::Editor.new(Reline.core.config)
    editor.instance_variable_set(:@buffer_of_lines, %w[a b c])
    Rvim::Command.execute(editor, Rvim::Command.parse(':99'))
    assert_equal 2, editor.line_index
  end

  def test_parse_substitute_simple
    parsed = Rvim::Command.parse(':s/foo/bar/')
    assert_equal :sub, parsed.verb
    assert_equal 'foo', parsed.sub[:pattern]
    assert_equal 'bar', parsed.sub[:replacement]
    assert_equal false, parsed.sub[:global]
    assert_equal :current, parsed.range
  end

  def test_parse_substitute_global
    parsed = Rvim::Command.parse(':s/foo/bar/g')
    assert_equal true, parsed.sub[:global]
  end

  def test_parse_substitute_whole_file
    parsed = Rvim::Command.parse(':%s/foo/bar/g')
    assert_equal :whole, parsed.range
  end

  def test_parse_substitute_line_range
    parsed = Rvim::Command.parse(':2,5s/foo/bar/')
    assert_equal [2, 5], parsed.range
  end

  def test_execute_substitute_replaces_first_only
    editor = Rvim::Editor.new(Reline.core.config)
    editor.instance_variable_set(:@buffer_of_lines, [+'foo foo foo'])
    Rvim::Command.execute(editor, Rvim::Command.parse(':s/foo/bar/'))
    assert_equal 'bar foo foo', editor.buffer_of_lines[0]
  end

  def test_execute_substitute_global
    editor = Rvim::Editor.new(Reline.core.config)
    editor.instance_variable_set(:@buffer_of_lines, [+'foo foo foo'])
    Rvim::Command.execute(editor, Rvim::Command.parse(':s/foo/bar/g'))
    assert_equal 'bar bar bar', editor.buffer_of_lines[0]
  end

  def test_parse_nmap
    parsed = Rvim::Command.parse(':nmap Y y$')
    assert_equal :nmap, parsed.verb
    assert_equal 'Y y$', parsed.arg
  end

  def test_parse_inoremap
    parsed = Rvim::Command.parse(':inoremap jk <Esc>')
    assert_equal :inoremap, parsed.verb
    assert_equal 'jk <Esc>', parsed.arg
  end

  def test_execute_nmap_registers_in_normal_mode
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap Y y$'))
    result, mapping = editor.keymap.lookup(:normal, 'Y')
    assert_equal :exact, result
    assert_equal 'y$', mapping.rhs
    assert_equal true, mapping.recursive
  end

  def test_execute_inoremap_registers_non_recursive
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':inoremap jk <Esc>'))
    result, mapping = editor.keymap.lookup(:insert, 'jk')
    assert_equal :exact, result
    assert_equal "\e", mapping.rhs
    assert_equal false, mapping.recursive
  end

  def test_execute_map_registers_in_three_modes
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':map Y y$'))
    %i[normal visual op_pending].each do |mode|
      result, _ = editor.keymap.lookup(mode, 'Y')
      assert_equal :exact, result, "expected :exact for #{mode}"
    end
    result, _ = editor.keymap.lookup(:insert, 'Y')
    assert_equal :none, result
  end

  def test_execute_unmap
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap Y y$'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':nunmap Y'))
    result, _ = editor.keymap.lookup(:normal, 'Y')
    assert_equal :none, result
  end

  def test_execute_mapclear
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap Y y$'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap X x'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmapclear'))
    assert_equal true, editor.keymap.empty?(:normal)
  end

  def test_execute_nmap_lhs_only_shows_listing
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap Y y$'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap Y'))
    assert_not_nil editor.list_view
    refute editor.list_view.lines.find { |l| l.include?('Y') }.nil?
  end

  def test_execute_map_with_leader
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap <leader>w :w<CR>'))
    result, mapping = editor.keymap.lookup(:normal, "\\w")
    assert_equal :exact, result
    assert_equal ":w\r", mapping.rhs
  end

  def test_let_mapleader_double_quoted
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':let mapleader = ","'))
    assert_equal ',', editor.let_vars['mapleader']
    assert_equal ',', editor.mapleader
  end

  def test_let_mapleader_single_quoted
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(":let mapleader = ' '"))
    assert_equal ' ', editor.mapleader
  end

  def test_let_mapleader_no_quotes
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':let mapleader = ;'))
    assert_equal ';', editor.mapleader
  end

  def test_mapping_after_let_uses_new_leader
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':let mapleader = ","'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap <leader>w :w<CR>'))
    result, _ = editor.keymap.lookup(:normal, ',w')
    assert_equal :exact, result
    # And the old backslash leader should NOT be registered
    result, _ = editor.keymap.lookup(:normal, "\\w")
    assert_equal :none, result
  end

  def test_mapping_before_let_keeps_old_leader
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap <leader>a aaa'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':let mapleader = ","'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap <leader>b bbb'))
    result, _ = editor.keymap.lookup(:normal, "\\a")
    assert_equal :exact, result
    result, _ = editor.keymap.lookup(:normal, ',b')
    assert_equal :exact, result
  end

  def test_let_invalid_arg_sets_status
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':let foo'))
    assert_match(/E121/, editor.status_message.to_s)
  end

  def test_map_no_args_lists_all_modes
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap Y y$'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':inoremap jk <Esc>'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap'))
    refute_nil editor.list_view
    body = editor.list_view.lines.join("\n")
    assert_match(/Y/, body)
    refute_match(/jk/, body) # nmap mode-only filter excludes insert mappings
  end

  def test_imap_no_args_lists_insert_only
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap Y y$'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':inoremap jk <Esc>'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':imap'))
    body = editor.list_view.lines.join("\n")
    assert_match(/jk/, body)
    refute_match(/Y/, body)
  end

  def test_listing_renders_nonprintable_rhs_as_tags
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':inoremap jk <Esc>'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':imap'))
    body = editor.list_view.lines.join("\n")
    assert_match(/<Esc>/, body)
  end

  def test_listing_marks_noremap_with_asterisk
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':inoremap jk <Esc>'))
    Rvim::Command.execute(editor, Rvim::Command.parse(':imap'))
    body = editor.list_view.lines.join("\n")
    assert_match(/i\*/, body)
  end

  def test_cmap_registers_in_cmdline_mode
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':cmap jk <Esc>'))
    result, _ = editor.keymap.lookup(:cmdline, 'jk')
    assert_equal :exact, result
  end

  def test_map_bang_registers_in_insert_and_cmdline
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':map! jk <Esc>'))
    %i[insert cmdline].each do |mode|
      result, _ = editor.keymap.lookup(mode, 'jk')
      assert_equal :exact, result, "expected :exact for #{mode}"
    end
    # Should NOT register in normal/visual/op_pending
    %i[normal visual op_pending].each do |mode|
      result, _ = editor.keymap.lookup(mode, 'jk')
      assert_equal :none, result, "expected :none for #{mode}"
    end
  end

  def test_silent_modifier_sets_flag
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap <silent> Y :w<CR>'))
    _, mapping = editor.keymap.lookup(:normal, 'Y')
    assert_equal true, mapping.silent
  end

  def test_no_silent_default
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap Y y$'))
    _, mapping = editor.keymap.lookup(:normal, 'Y')
    assert_equal false, mapping.silent
  end

  def test_unknown_modifiers_are_silently_consumed
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap <buffer> <silent> Y y$'))
    result, mapping = editor.keymap.lookup(:normal, 'Y')
    assert_equal :exact, result
    assert_equal true, mapping.silent
  end
end
