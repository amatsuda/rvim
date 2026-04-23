# frozen_string_literal: true

require_relative 'test_helper'

class TestInccommandStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_nosplit
    assert_equal 'nosplit', @editor.settings.get(:inccommand)
  end

  def test_icm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set icm=split'))
    assert_equal 'split', @editor.settings.get(:inccommand)
  end
end

class TestPumblendStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:pumblend)
  end

  def test_set_pumblend
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pumblend=15'))
    assert_equal 15, @editor.settings.get(:pumblend)
  end
end

class TestWinblendStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:winblend)
  end

  def test_winbl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set winbl=20'))
    assert_equal 20, @editor.settings.get(:winblend)
  end
end

class TestMousescrollStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_ver_hor
    assert_equal 'ver:3,hor:6', @editor.settings.get(:mousescroll)
  end

  def test_set_mousescroll
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mousescroll=ver:1,hor:1'))
    assert_equal 'ver:1,hor:1', @editor.settings.get(:mousescroll)
  end
end

class TestCinscopedeclsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_public_etc
    assert_match(/public/, @editor.settings.get(:cinscopedecls))
  end

  def test_cinsd_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cinsd=public'))
    assert_equal 'public', @editor.settings.get(:cinscopedecls)
  end
end
