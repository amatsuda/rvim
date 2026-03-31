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

  def test_execute_map_missing_rhs_sets_status
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap Y'))
    assert_match(/E474/, editor.status_message.to_s)
  end

  def test_execute_map_with_leader
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(editor, Rvim::Command.parse(':nmap <leader>w :w<CR>'))
    result, mapping = editor.keymap.lookup(:normal, "\\w")
    assert_equal :exact, result
    assert_equal ":w\r", mapping.rhs
  end
end
