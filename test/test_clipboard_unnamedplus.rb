# frozen_string_literal: true

require_relative 'test_helper'

# When &clipboard contains 'unnamedplus' (or 'unnamed'), the unnamed
# register `"` aliases the system clipboard for both write and read.
# Yank `y` writes to pbcopy; paste `p` reads from pbpaste.
class TestClipboardUnnamedPlus < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @writes = []
    @system_text = ''
    Rvim::SystemClipboard.singleton_class.alias_method(:_orig_write, :write) unless Rvim::SystemClipboard.singleton_class.method_defined?(:_orig_write)
    Rvim::SystemClipboard.singleton_class.alias_method(:_orig_read, :read) unless Rvim::SystemClipboard.singleton_class.method_defined?(:_orig_read)
    writes_ref = @writes
    text_ref = -> { @system_text }
    Rvim::SystemClipboard.define_singleton_method(:write) { |s| writes_ref << s }
    Rvim::SystemClipboard.define_singleton_method(:read)  { text_ref.call }
  end

  def teardown
    Rvim::SystemClipboard.singleton_class.send(:alias_method, :write, :_orig_write)
    Rvim::SystemClipboard.singleton_class.send(:alias_method, :read, :_orig_read)
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def setup_buffer(text, byte_pointer: 0)
    @editor.instance_variable_set(:@buffer_of_lines, [+text])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, byte_pointer)
    @editor.config.editing_mode = :vi_command
  end

  def test_p_reads_from_system_clipboard_with_unnamedplus
    @editor.settings.set(:clipboard, 'unnamedplus')
    @system_text = 'PASTED'
    setup_buffer('AB', byte_pointer: 0)
    send_keys('p')
    assert_equal 'APASTEDB', @editor.buffer_of_lines[0]
  end

  def test_p_reads_from_system_clipboard_with_unnamed
    @editor.settings.set(:clipboard, 'unnamed')
    @system_text = 'X'
    setup_buffer('YZ', byte_pointer: 0)
    send_keys('p')
    assert_equal 'YXZ', @editor.buffer_of_lines[0]
  end

  def test_p_uses_internal_register_without_clipboard_setting
    @editor.settings.set(:clipboard, '')
    @editor.write_register('LOCAL', :char, register: '"')
    setup_buffer('ab', byte_pointer: 0)
    send_keys('p')
    assert_equal 'aLOCALb', @editor.buffer_of_lines[0]
  end

  def test_round_trip_y_then_p_with_unnamedplus
    @editor.settings.set(:clipboard, 'unnamedplus')
    setup_buffer('hello world', byte_pointer: 0)
    send_keys('y', 'w')
    refute_empty @writes
    @system_text = @writes.last
    setup_buffer('xy', byte_pointer: 0)
    send_keys('p')
    assert_match(/hello/, @editor.buffer_of_lines[0])
  end

  def test_capital_P_also_reads_from_system_clipboard
    @editor.settings.set(:clipboard, 'unnamedplus')
    @system_text = 'X'
    setup_buffer('AB', byte_pointer: 1) # cursor on 'B'
    send_keys('P')
    # P pastes BEFORE cursor.
    assert_equal 'AXB', @editor.buffer_of_lines[0]
  end
end
