# frozen_string_literal: true

require_relative 'test_helper'

class TestMagicStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:magic)
  end

  def test_set_nomagic
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nomagic'))
    assert_equal false, @editor.settings.get(:magic)
  end
end

class TestEadirection < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    buf = Rvim::Buffer.new(1, nil)
    @editor.instance_variable_set(:@current_buffer, buf)
    @initial = Rvim::Window.new(buf)
    @initial.extra_rows = 5
    @initial.extra_cols = 7
    @editor.instance_variable_set(:@windows, [@initial])
    @editor.instance_variable_set(:@current_window, @initial)
  end

  def test_default_both_zeros_extras
    @editor.settings.set(:eadirection, 'both')
    @editor.equalize_windows
    assert_equal 0, @initial.extra_rows
    assert_equal 0, @initial.extra_cols
  end

  def test_hor_only_zeros_rows
    @editor.settings.set(:eadirection, 'hor')
    @editor.equalize_windows
    assert_equal 0, @initial.extra_rows
    assert_equal 7, @initial.extra_cols
  end

  def test_ver_only_zeros_cols
    @editor.settings.set(:eadirection, 'ver')
    @editor.equalize_windows
    assert_equal 5, @initial.extra_rows
    assert_equal 0, @initial.extra_cols
  end

  def test_ead_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ead=hor'))
    assert_equal 'hor', @editor.settings.get(:eadirection)
  end
end

class TestCompleteopt < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def test_default_menu
    assert_equal 'menu', @editor.settings.get(:completeopt)
  end

  def test_cot_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cot=menu,noinsert'))
    assert_equal 'menu,noinsert', @editor.settings.get(:completeopt)
  end

  def test_default_replaces_base_with_first_candidate
    @editor.instance_variable_set(:@buffer_of_lines, ['hello hero help'.dup, 'he'.dup])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.send(:start_completion, +1)
    assert_equal 'hello', @editor.buffer_of_lines[1]
  end

  def test_noinsert_keeps_base_text
    @editor.settings.set(:completeopt, 'menu,noinsert')
    @editor.instance_variable_set(:@buffer_of_lines, ['hello hero help'.dup, 'he'.dup])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.send(:start_completion, +1)
    # Buffer text unchanged; popup is still active so user can pick
    assert_equal 'he', @editor.buffer_of_lines[1]
    assert_equal true, @editor.completion_active
    refute_nil @editor.completion_popup
  end
end
