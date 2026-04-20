# frozen_string_literal: true

require_relative 'test_helper'

class TestIndentkeysStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_braces
    assert_match(/0\}/, @editor.settings.get(:indentkeys))
  end

  def test_indk_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set indk=0=,0)'))
    assert_equal '0=,0)', @editor.settings.get(:indentkeys)
  end
end

class TestFoldexprStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal '0', @editor.settings.get(:foldexpr)
  end

  def test_fde_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fde=indent(v:lnum)'))
    assert_equal 'indent(v:lnum)', @editor.settings.get(:foldexpr)
  end
end

class TestFoldtextStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_foldtext
    assert_equal 'foldtext()', @editor.settings.get(:foldtext)
  end

  def test_fdt_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fdt=MyFold()'))
    assert_equal 'MyFold()', @editor.settings.get(:foldtext)
  end
end

class TestFoldminlinesStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one
    assert_equal 1, @editor.settings.get(:foldminlines)
  end

  def test_fml_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fml=3'))
    assert_equal 3, @editor.settings.get(:foldminlines)
  end
end

class TestFoldnestmaxStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_twenty
    assert_equal 20, @editor.settings.get(:foldnestmax)
  end

  def test_fdn_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fdn=5'))
    assert_equal 5, @editor.settings.get(:foldnestmax)
  end
end
