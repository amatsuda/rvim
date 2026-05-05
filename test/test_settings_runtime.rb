# frozen_string_literal: true

require_relative 'test_helper'

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

class TestSuffixesStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_bak
    assert_match(/\.bak/, @editor.settings.get(:suffixes))
  end

  def test_su_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set su=.tmp,.o'))
    assert_equal '.tmp,.o', @editor.settings.get(:suffixes)
  end
end

class TestSuffixesaddStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:suffixesadd)
  end

  def test_sua_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sua=.rb,.erb'))
    assert_equal '.rb,.erb', @editor.settings.get(:suffixesadd)
  end
end

class TestFiletypeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:filetype)
  end

  def test_ft_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ft=ruby'))
    assert_equal 'ruby', @editor.settings.get(:filetype)
  end
end

class TestEventignoreStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:eventignore)
  end

  def test_ei_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ei=BufEnter,BufLeave'))
    assert_equal 'BufEnter,BufLeave', @editor.settings.get(:eventignore)
  end
end

class TestLoadpluginsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:loadplugins)
  end

  def test_lpl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nolpl'))
    assert_equal false, @editor.settings.get(:loadplugins)
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
