# frozen_string_literal: true

require_relative 'test_helper'

class TestRuntimepathStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_dotvim
    assert_match(/\.vim/, @editor.settings.get(:runtimepath))
  end

  def test_rtp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set rtp=~/.config/rvim'))
    assert_equal '~/.config/rvim', @editor.settings.get(:runtimepath)
  end
end

class TestCdpathStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_relative
    assert_equal ',,', @editor.settings.get(:cdpath)
  end

  def test_cd_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cd=,,~/src'))
    assert_equal ',,~/src', @editor.settings.get(:cdpath)
  end
end

class TestDefineStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_cpp
    assert_match(/define/, @editor.settings.get(:define))
  end

  def test_def_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set def=^def\\\\s'))
    assert_match(/def/, @editor.settings.get(:define))
  end
end

class TestIncludeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_cpp
    assert_match(/include/, @editor.settings.get(:include))
  end

  def test_inc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set inc=^require'))
    assert_equal '^require', @editor.settings.get(:include)
  end
end

class TestSessionoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_buffers
    assert_match(/buffers/, @editor.settings.get(:sessionoptions))
  end

  def test_ssop_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ssop=buffers,curdir'))
    assert_equal 'buffers,curdir', @editor.settings.get(:sessionoptions)
  end
end
