# frozen_string_literal: true

require_relative 'test_helper'

class TestCpoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_vim_compat_flags
    assert_equal 'aABceFs', @editor.settings.get(:cpoptions)
  end

  def test_cpo_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cpo=aB'))
    assert_equal 'aB', @editor.settings.get(:cpoptions)
  end
end

class TestDisplayStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_lastline
    assert_equal 'lastline', @editor.settings.get(:display)
  end

  def test_dy_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set dy=truncate'))
    assert_equal 'truncate', @editor.settings.get(:display)
  end
end

class TestFillcharsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:fillchars)
  end

  def test_fcs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fcs=vert:|,fold:-'))
    assert_equal 'vert:|,fold:-', @editor.settings.get(:fillchars)
  end
end

class TestTablineStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:tabline)
  end

  def test_tal_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tal=%!MyTabLine()'))
    assert_equal '%!MyTabLine()', @editor.settings.get(:tabline)
  end
end

class TestVerboseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:verbose)
  end

  def test_vbs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vbs=9'))
    assert_equal 9, @editor.settings.get(:verbose)
  end
end
