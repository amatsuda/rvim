# frozen_string_literal: true

require_relative 'test_helper'

class TestRevinsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:revins)
  end

  def test_ri_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ri'))
    assert_equal true, @editor.settings.get(:revins)
  end
end

class TestRightleftStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:rightleft)
  end

  def test_rl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set rl'))
    assert_equal true, @editor.settings.get(:rightleft)
  end
end

class TestRightleftcmdStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_search
    assert_equal 'search', @editor.settings.get(:rightleftcmd)
  end

  def test_rlc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set rlc=search'))
    assert_equal 'search', @editor.settings.get(:rightleftcmd)
  end
end

class TestFileformatsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_unix_dos
    assert_equal 'unix,dos', @editor.settings.get(:fileformats)
  end

  def test_ffs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ffs=unix,dos,mac'))
    assert_equal 'unix,dos,mac', @editor.settings.get(:fileformats)
  end
end

class TestFileignorecaseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:fileignorecase)
  end

  def test_fic_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fic'))
    assert_equal true, @editor.settings.get(:fileignorecase)
  end
end
