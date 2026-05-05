# frozen_string_literal: true

require_relative 'test_helper'

class TestBelloff < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_all
    assert_equal 'all', @editor.settings.get(:belloff)
  end

  def test_bo_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set bo=esc'))
    assert_equal 'esc', @editor.settings.get(:belloff)
  end
end

class TestMousehideStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:mousehide)
  end

  def test_mh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nomousehide'))
    assert_equal false, @editor.settings.get(:mousehide)
  end
end

class TestMousemodelStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_extend
    assert_equal 'extend', @editor.settings.get(:mousemodel)
  end

  def test_mousem_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mousem=popup'))
    assert_equal 'popup', @editor.settings.get(:mousemodel)
  end
end

class TestMousetimeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_five_hundred
    assert_equal 500, @editor.settings.get(:mousetime)
  end

  def test_mouset_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mouset=200'))
    assert_equal 200, @editor.settings.get(:mousetime)
  end
end

class TestIminsertStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:iminsert)
  end

  def test_imi_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set imi=2'))
    assert_equal 2, @editor.settings.get(:iminsert)
  end
end

class TestImsearchStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_minus_one
    assert_equal(-1, @editor.settings.get(:imsearch))
  end

  def test_ims_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ims=0'))
    assert_equal 0, @editor.settings.get(:imsearch)
  end
end

class TestErrorbellsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:errorbells)
  end

  def test_eb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set eb'))
    assert_equal true, @editor.settings.get(:errorbells)
  end
end

class TestVisualbellStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:visualbell)
  end

  def test_vb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vb'))
    assert_equal true, @editor.settings.get(:visualbell)
  end
end

class TestTtyfastStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:ttyfast)
  end

  def test_tf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notf'))
    assert_equal false, @editor.settings.get(:ttyfast)
  end
end

class TestTermguicolorsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:termguicolors)
  end

  def test_tgc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tgc'))
    assert_equal true, @editor.settings.get(:termguicolors)
  end
end

class TestTermencodingStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:termencoding)
  end

  def test_tenc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tenc=utf-8'))
    assert_equal 'utf-8', @editor.settings.get(:termencoding)
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
