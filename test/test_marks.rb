# frozen_string_literal: true

require_relative 'test_helper'

class TestMarks < Test::Unit::TestCase
  def setup
    @marks = Rvim::Marks.new
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_set_and_get
    @marks.set('a', 3, 5)
    assert_equal [3, 5], @marks.get('a', @editor)
  end

  def test_get_unset_returns_nil
    assert_nil @marks.get('z', @editor)
  end

  def test_set_invalid_name_is_noop
    @marks.set('A', 1, 0)
    @marks.set('1', 1, 0)
    assert_nil @marks.get('A', @editor)
  end

  def test_clear
    @marks.set('a', 1, 1)
    @marks.clear
    assert_nil @marks.get('a', @editor)
  end

  def test_visual_marks_resolve_via_editor
    @editor.instance_variable_set(:@last_visual, { anchor: [1, 2], last_end: [3, 4], mode: :char })
    assert_equal [1, 2], @marks.get('<', @editor)
    assert_equal [3, 4], @marks.get('>', @editor)
  end

  def test_visual_marks_nil_when_no_last_visual
    assert_nil @marks.get('<', @editor)
  end
end
