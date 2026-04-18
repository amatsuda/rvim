# frozen_string_literal: true

require_relative 'test_helper'

class TestWinfixheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:winfixheight)
  end

  def test_wfh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wfh'))
    assert_equal true, @editor.settings.get(:winfixheight)
  end
end

class TestWinfixwidthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:winfixwidth)
  end

  def test_wfw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wfw'))
    assert_equal true, @editor.settings.get(:winfixwidth)
  end
end

class TestCscopetagStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:cscopetag)
  end

  def test_cst_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cst'))
    assert_equal true, @editor.settings.get(:cscopetag)
  end
end

class TestCscopeprgStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_cscope
    assert_equal 'cscope', @editor.settings.get(:cscopeprg)
  end

  def test_csprg_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csprg=/usr/local/bin/cscope'))
    assert_equal '/usr/local/bin/cscope', @editor.settings.get(:cscopeprg)
  end
end

class TestCscopetagorderStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:cscopetagorder)
  end

  def test_csto_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csto=1'))
    assert_equal 1, @editor.settings.get(:cscopetagorder)
  end
end
