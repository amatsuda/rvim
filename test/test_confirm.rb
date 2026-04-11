# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestConfirmPromptApi < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def k(ch)
    Reline::Key.new(ch, nil, false)
  end

  def test_confirm_prompt_arms_question
    @editor.confirm_prompt('Save changes?', %w[y n c]) { |c| @answer = c }
    assert_equal 'Save changes?', @editor.confirm_question
    assert_equal %w[y n c], @editor.confirm_options
  end

  def test_y_fires_callback
    @answer = nil
    @editor.confirm_prompt('OK?', %w[y n]) { |c| @answer = c }
    @editor.update(k('y'))
    assert_equal 'y', @answer
    assert_nil @editor.confirm_question
  end

  def test_n_fires_callback
    @answer = nil
    @editor.confirm_prompt('OK?', %w[y n]) { |c| @answer = c }
    @editor.update(k('n'))
    assert_equal 'n', @answer
  end

  def test_case_insensitive
    @answer = nil
    @editor.confirm_prompt('OK?', %w[y n]) { |c| @answer = c }
    @editor.update(k('Y'))
    assert_equal 'y', @answer
  end

  def test_esc_cancels
    @editor.confirm_prompt('OK?', %w[y n]) { |c| @answer = c }
    @editor.update(k("\e"))
    assert_nil @editor.confirm_question
  end

  def test_invalid_key_keeps_prompt_active
    @editor.confirm_prompt('OK?', %w[y n]) { |_c| flunk 'should not fire' }
    @editor.update(k('z'))
    refute_nil @editor.confirm_question
  end
end

class TestConfirmQuit < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:confirm, true)
  end

  def k(ch)
    Reline::Key.new(ch, nil, false)
  end

  def with_modified_file
    f = Tempfile.new(['cf', '.txt'])
    f.binmode; f.write("orig\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.modified = true
    yield f
  ensure
    f&.unlink
  end

  def test_q_with_modified_buffer_arms_confirm
    with_modified_file do |_|
      Rvim::Command.execute(@editor, Rvim::Command.parse(':q'))
      assert_match(/Save changes/, @editor.confirm_question.to_s)
      assert_equal false, @editor.quit?
    end
  end

  def test_y_saves_and_quits
    with_modified_file do |f|
      Rvim::Command.execute(@editor, Rvim::Command.parse(':q'))
      @editor.update(k('y'))
      assert_match(/changed/, File.read(f.path))
      assert_equal true, @editor.quit?
    end
  end

  def test_n_quits_without_saving
    with_modified_file do |f|
      Rvim::Command.execute(@editor, Rvim::Command.parse(':q'))
      @editor.update(k('n'))
      assert_equal 'orig', File.read(f.path).chomp
      assert_equal true, @editor.quit?
    end
  end

  def test_c_cancels
    with_modified_file do |f|
      Rvim::Command.execute(@editor, Rvim::Command.parse(':q'))
      @editor.update(k('c'))
      assert_match(/Cancel/, @editor.status_message.to_s)
      assert_equal false, @editor.quit?
      assert_equal 'orig', File.read(f.path).chomp
    end
  end

  def test_no_confirm_setting_falls_back_to_e37
    with_modified_file do |_|
      @editor.settings.set(:confirm, false)
      Rvim::Command.execute(@editor, Rvim::Command.parse(':q'))
      assert_match(/E37/, @editor.status_message.to_s)
      assert_nil @editor.confirm_question
    end
  end
end
