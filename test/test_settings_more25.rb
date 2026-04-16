# frozen_string_literal: true

require_relative 'test_helper'

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

class TestWrapmarginStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:wrapmargin)
  end

  def test_wm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wm=5'))
    assert_equal 5, @editor.settings.get(:wrapmargin)
  end
end

class TestSelectionStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_inclusive
    assert_equal 'inclusive', @editor.settings.get(:selection)
  end

  def test_sel_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sel=exclusive'))
    assert_equal 'exclusive', @editor.settings.get(:selection)
  end
end

class TestSelectmodeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:selectmode)
  end

  def test_slm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set slm=mouse,key'))
    assert_equal 'mouse,key', @editor.settings.get(:selectmode)
  end
end
