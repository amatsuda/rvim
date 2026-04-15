# frozen_string_literal: true

require_relative 'test_helper'

class TestFormatoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_tcq
    assert_equal 'tcq', @editor.settings.get(:formatoptions)
  end

  def test_fo_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fo=tcqj'))
    assert_equal 'tcqj', @editor.settings.get(:formatoptions)
  end
end

class TestCommentsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_slashes
    assert_match(%r{//}, @editor.settings.get(:comments))
  end

  def test_com_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set com=:#'))
    assert_equal ':#', @editor.settings.get(:comments)
  end
end

class TestCommentstringStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_block
    assert_equal '/*%s*/', @editor.settings.get(:commentstring)
  end

  def test_cms_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cms=#%s'))
    assert_equal '#%s', @editor.settings.get(:commentstring)
  end
end

class TestPathStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_local
    assert_equal '.,,', @editor.settings.get(:path)
  end

  def test_pa_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pa=.,/usr/include'))
    assert_equal '.,/usr/include', @editor.settings.get(:path)
  end
end

class TestWinminheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one
    assert_equal 1, @editor.settings.get(:winminheight)
  end

  def test_wmh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wmh=0'))
    assert_equal 0, @editor.settings.get(:winminheight)
  end
end
