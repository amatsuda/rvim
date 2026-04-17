# frozen_string_literal: true

require_relative 'test_helper'

class TestCinkeysStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_braces
    assert_match(/0\{/, @editor.settings.get(:cinkeys))
  end

  def test_cink_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cink=0},0)'))
    assert_equal '0},0)', @editor.settings.get(:cinkeys)
  end
end

class TestHelpheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_twenty
    assert_equal 20, @editor.settings.get(:helpheight)
  end

  def test_hh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set hh=15'))
    assert_equal 15, @editor.settings.get(:helpheight)
  end
end

class TestHelplangStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_en
    assert_equal 'en', @editor.settings.get(:helplang)
  end

  def test_hlg_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set hlg=ja,en'))
    assert_equal 'ja,en', @editor.settings.get(:helplang)
  end
end

class TestTagcaseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_followic
    assert_equal 'followic', @editor.settings.get(:tagcase)
  end

  def test_tc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tc=match'))
    assert_equal 'match', @editor.settings.get(:tagcase)
  end
end

class TestTagstackStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:tagstack)
  end

  def test_tgst_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notagstack'))
    assert_equal false, @editor.settings.get(:tagstack)
  end
end
