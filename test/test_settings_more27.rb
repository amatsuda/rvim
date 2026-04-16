# frozen_string_literal: true

require_relative 'test_helper'

class TestSwapfileStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:swapfile)
  end

  def test_swf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set noswapfile'))
    assert_equal false, @editor.settings.get(:swapfile)
  end
end

class TestDirectoryStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_tmp
    assert_match(%r{/tmp}, @editor.settings.get(:directory))
  end

  def test_dir_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set dir=/var/tmp'))
    assert_equal '/var/tmp', @editor.settings.get(:directory)
  end
end

class TestUpdatecountStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_two_hundred
    assert_equal 200, @editor.settings.get(:updatecount)
  end

  def test_uc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set uc=0'))
    assert_equal 0, @editor.settings.get(:updatecount)
  end
end

class TestViewdirStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default
    assert_match(%r{view}, @editor.settings.get(:viewdir))
  end

  def test_vdir_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vdir=~/.cache/rvim/view'))
    assert_equal '~/.cache/rvim/view', @editor.settings.get(:viewdir)
  end
end

class TestViewoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_folds
    assert_match(/folds/, @editor.settings.get(:viewoptions))
  end

  def test_vop_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vop=folds,cursor'))
    assert_equal 'folds,cursor', @editor.settings.get(:viewoptions)
  end
end
