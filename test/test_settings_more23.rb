# frozen_string_literal: true

require_relative 'test_helper'

class TestWinheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one
    assert_equal 1, @editor.settings.get(:winheight)
  end

  def test_wh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wh=10'))
    assert_equal 10, @editor.settings.get(:winheight)
  end
end

class TestWinwidthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_twenty
    assert_equal 20, @editor.settings.get(:winwidth)
  end

  def test_wiw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wiw=40'))
    assert_equal 40, @editor.settings.get(:winwidth)
  end
end

class TestWinminwidthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one
    assert_equal 1, @editor.settings.get(:winminwidth)
  end

  def test_wmw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wmw=0'))
    assert_equal 0, @editor.settings.get(:winminwidth)
  end
end

class TestSynmaxcolStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_three_thousand
    assert_equal 3000, @editor.settings.get(:synmaxcol)
  end

  def test_smc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set smc=200'))
    assert_equal 200, @editor.settings.get(:synmaxcol)
  end
end

class TestRedrawtimeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_two_thousand
    assert_equal 2000, @editor.settings.get(:redrawtime)
  end

  def test_rdt_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set rdt=500'))
    assert_equal 500, @editor.settings.get(:redrawtime)
  end
end
