# frozen_string_literal: true

require_relative 'test_helper'

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
