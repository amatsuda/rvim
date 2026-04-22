# frozen_string_literal: true

require_relative 'test_helper'

class TestIsprintStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default
    assert_match(/161/, @editor.settings.get(:isprint))
  end

  def test_isp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set isp=@,161-255'))
    assert_equal '@,161-255', @editor.settings.get(:isprint)
  end
end

class TestHelpfileStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_help_txt
    assert_match(%r{help\.txt}, @editor.settings.get(:helpfile))
  end

  def test_hf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set hf=/usr/share/vim/doc/help.txt'))
    assert_equal '/usr/share/vim/doc/help.txt', @editor.settings.get(:helpfile)
  end
end

class TestLangnoremapStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:langnoremap)
  end

  def test_set_nolangnoremap
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nolangnoremap'))
    assert_equal false, @editor.settings.get(:langnoremap)
  end
end

class TestLangmenuStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:langmenu)
  end

  def test_lm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lm=ja_JP'))
    assert_equal 'ja_JP', @editor.settings.get(:langmenu)
  end
end

class TestQuickfixtextfuncStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:quickfixtextfunc)
  end

  def test_qftf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set qftf=MyQfText'))
    assert_equal 'MyQfText', @editor.settings.get(:quickfixtextfunc)
  end
end
