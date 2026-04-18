# frozen_string_literal: true

require_relative 'test_helper'

class TestLangmapStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:langmap)
  end

  def test_lmap_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lmap=jk;hl'))
    assert_equal 'jk;hl', @editor.settings.get(:langmap)
  end
end

class TestLangremapStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:langremap)
  end

  def test_set_langremap
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set langremap'))
    assert_equal true, @editor.settings.get(:langremap)
  end
end

class TestRegexpengineStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero_auto
    assert_equal 0, @editor.settings.get(:regexpengine)
  end

  def test_re_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set re=2'))
    assert_equal 2, @editor.settings.get(:regexpengine)
  end
end

class TestTaglengthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:taglength)
  end

  def test_set_taglength
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set taglength=10'))
    assert_equal 10, @editor.settings.get(:taglength)
  end
end

class TestTagrelativeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:tagrelative)
  end

  def test_tr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notagrelative'))
    assert_equal false, @editor.settings.get(:tagrelative)
  end
end
