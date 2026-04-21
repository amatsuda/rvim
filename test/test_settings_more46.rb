# frozen_string_literal: true

require_relative 'test_helper'

class TestDelcombineStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:delcombine)
  end

  def test_deco_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set deco'))
    assert_equal true, @editor.settings.get(:delcombine)
  end
end

class TestEmojiStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:emoji)
  end

  def test_emo_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set noemoji'))
    assert_equal false, @editor.settings.get(:emoji)
  end
end

class TestTerseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:terse)
  end

  def test_set_terse
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set terse'))
    assert_equal true, @editor.settings.get(:terse)
  end
end

class TestWarnStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:warn)
  end

  def test_set_nowarn
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nowarn'))
    assert_equal false, @editor.settings.get(:warn)
  end
end

class TestTagbsearchStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:tagbsearch)
  end

  def test_tbs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notbs'))
    assert_equal false, @editor.settings.get(:tagbsearch)
  end
end
