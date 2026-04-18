# frozen_string_literal: true

require_relative 'test_helper'

class TestMousehideStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:mousehide)
  end

  def test_mh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nomousehide'))
    assert_equal false, @editor.settings.get(:mousehide)
  end
end

class TestMousemodelStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_extend
    assert_equal 'extend', @editor.settings.get(:mousemodel)
  end

  def test_mousem_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mousem=popup'))
    assert_equal 'popup', @editor.settings.get(:mousemodel)
  end
end

class TestMousetimeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_five_hundred
    assert_equal 500, @editor.settings.get(:mousetime)
  end

  def test_mouset_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mouset=200'))
    assert_equal 200, @editor.settings.get(:mousetime)
  end
end

class TestIminsertStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:iminsert)
  end

  def test_imi_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set imi=2'))
    assert_equal 2, @editor.settings.get(:iminsert)
  end
end

class TestImsearchStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_minus_one
    assert_equal(-1, @editor.settings.get(:imsearch))
  end

  def test_ims_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ims=0'))
    assert_equal 0, @editor.settings.get(:imsearch)
  end
end
