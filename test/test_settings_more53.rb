# frozen_string_literal: true

require_relative 'test_helper'

class TestRestorescreenStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:restorescreen)
  end

  def test_rs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nors'))
    assert_equal false, @editor.settings.get(:restorescreen)
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

class TestViminfofileStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:viminfofile)
  end

  def test_vif_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vif=~/.cache/rvim/info'))
    assert_equal '~/.cache/rvim/info', @editor.settings.get(:viminfofile)
  end
end

class TestSmoothscrollStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:smoothscroll)
  end

  def test_set_smoothscroll
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set smoothscroll'))
    assert_equal true, @editor.settings.get(:smoothscroll)
  end
end

class TestStatuscolumnStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:statuscolumn)
  end

  def test_set_statuscolumn
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set statuscolumn=%s%l'))
    assert_equal '%s%l', @editor.settings.get(:statuscolumn)
  end
end
