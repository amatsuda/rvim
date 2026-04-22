# frozen_string_literal: true

require_relative 'test_helper'

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

class TestWildignorecaseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:wildignorecase)
  end

  def test_wic_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wic'))
    assert_equal true, @editor.settings.get(:wildignorecase)
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

class TestTabpagemaxStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_fifty
    assert_equal 50, @editor.settings.get(:tabpagemax)
  end

  def test_tpm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tpm=10'))
    assert_equal 10, @editor.settings.get(:tabpagemax)
  end
end
