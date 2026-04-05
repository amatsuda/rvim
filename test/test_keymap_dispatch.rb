# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestKeymapDispatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello world'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.config.editing_mode = :vi_command
  end

  def k(ch, sym = nil)
    Reline::Key.new(ch, sym, false)
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_nmap_Y_yanks_to_eol
    Rvim::Command.execute(@editor, Rvim::Command.parse(':nmap Y y$'))
    send_keys('Y')
    entry = @editor.read_register('"')
    assert_not_nil entry, 'register " should be set'
    assert_equal 'hello world', entry.text
  end

  def test_inoremap_jk_exits_insert_mode
    @editor.config.editing_mode = :vi_insert
    Rvim::Command.execute(@editor, Rvim::Command.parse(':inoremap jk <Esc>'))
    send_keys('j')
    # After 'j' alone, mapping is in :prefix state — not yet committed
    assert_equal :vi_insert, @editor.editing_mode_label
    send_keys('k')
    # Now jk → Esc fires
    assert_equal :vi_command, @editor.editing_mode_label
  end

  def test_partial_match_flushes_on_non_extending_key
    @editor.config.editing_mode = :vi_insert
    Rvim::Command.execute(@editor, Rvim::Command.parse(':inoremap jk <Esc>'))
    send_keys('j')
    # j is held as pending prefix
    assert_equal 'hello world', @editor.buffer_of_lines[0]
    send_keys('x')
    # 'jx' has no full match — flush both literally
    assert_equal 'jxhello world', @editor.buffer_of_lines[0]
  end

  def test_recursion_limit_prevents_infinite_loop
    Rvim::Command.execute(@editor, Rvim::Command.parse(':nmap a b'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':nmap b a'))
    send_keys('a')
    assert_match(/E223/, @editor.status_message.to_s)
  end

  def test_noremap_breaks_recursion
    # nnoremap a b: a → b (non-recursive), so even if b is also mapped,
    # the b inside the RHS isn't re-mapped.
    @editor.instance_variable_set(:@buffer_of_lines, [+'one', +'two', +'three'])
    @editor.instance_variable_set(:@line_index, 2)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':nnoremap a b'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':nmap b a'))
    # Without noremap, this would cycle. With nnoremap a b, sending 'a'
    # dispatches raw 'b' (vi_prev_word). It should not recurse.
    send_keys('a')
    assert_nil @editor.status_message # no E223
  end

  def test_multi_key_lhs_with_leader
    Rvim::Command.execute(@editor, Rvim::Command.parse(':nmap <leader>x x'))
    @editor.instance_variable_set(:@buffer_of_lines, [+'abc'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    send_keys('\\', 'x')
    # \x → x → vi_delete_next_char on 'a'
    assert_equal 'bc', @editor.buffer_of_lines[0]
  end

  def test_mapping_skipped_in_command_prompt
    Rvim::Command.execute(@editor, Rvim::Command.parse(':inoremap jk <Esc>'))
    @editor.send(:rvim_enter_command_mode, nil)
    # Now in :ex prompt — typing j then k should NOT trigger Esc.
    @editor.update(k('j'))
    @editor.update(k('k'))
    assert_equal 'jk', @editor.prompt_buffer
  end

  def test_let_mapleader_then_mapping_uses_comma
    Rvim::Command.execute(@editor, Rvim::Command.parse(':let mapleader = ","'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':nmap <leader>x x'))
    @editor.instance_variable_set(:@buffer_of_lines, [+'abc'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    send_keys(',', 'x')
    assert_equal 'bc', @editor.buffer_of_lines[0]
  end

  def test_arrow_key_lhs_in_mapping
    @editor.instance_variable_set(:@buffer_of_lines, [+'one', +'two', +'three'])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 0)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':nmap <Up> gg'))
    # Reline emits arrow keys as a single char string "\e[A"
    @editor.update(Reline::Key.new("\e[A", :ed_prev_history, false))
    # gg → first line
    assert_equal 0, @editor.line_index
  end

  def test_cmap_fires_during_ex_prompt
    Rvim::Command.execute(@editor, Rvim::Command.parse(':cnoremap jk <Esc>'))
    @editor.send(:rvim_enter_command_mode, nil)
    assert_equal :ex, @editor.prompt_mode
    @editor.update(k('j'))
    @editor.update(k('k'))
    # jk → Esc cancels the prompt
    assert_nil @editor.prompt_mode
  end

  def test_silent_mapping_suppresses_status
    @editor.instance_variable_set(:@buffer_of_lines, [+'first'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.status_message = 'preserve me'
    Rvim::Command.execute(@editor, Rvim::Command.parse(':nmap <silent> Y y$'))
    send_keys('Y')
    assert_equal 'preserve me', @editor.status_message
  end

  def test_init_vim_loaded_mappings
    f = Tempfile.new(['init', '.vim'])
    f.write("nmap Y y$\ninoremap jk <Esc>\n")
    f.close
    @editor.source(f.path)
    result, mapping = @editor.keymap.lookup(:normal, 'Y')
    assert_equal :exact, result
    assert_equal 'y$', mapping.rhs
    result, mapping = @editor.keymap.lookup(:insert, 'jk')
    assert_equal :exact, result
    assert_equal "\e", mapping.rhs
  ensure
    f&.unlink
  end
end
