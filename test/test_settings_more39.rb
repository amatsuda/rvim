# frozen_string_literal: true

require_relative 'test_helper'

class TestOmnifuncStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:omnifunc)
  end

  def test_ofu_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ofu=MyOmni'))
    assert_equal 'MyOmni', @editor.settings.get(:omnifunc)
  end
end

class TestOperatorfuncStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:operatorfunc)
  end

  def test_opfunc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set opfunc=MyOp'))
    assert_equal 'MyOp', @editor.settings.get(:operatorfunc)
  end
end

class TestTagfuncStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:tagfunc)
  end

  def test_tfu_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tfu=MyTag'))
    assert_equal 'MyTag', @editor.settings.get(:tagfunc)
  end
end

class TestFormatexprStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:formatexpr)
  end

  def test_fex_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fex=MyFmt()'))
    assert_equal 'MyFmt()', @editor.settings.get(:formatexpr)
  end
end

class TestIndentexprStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:indentexpr)
  end

  def test_inde_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set inde=GetRubyIndent()'))
    assert_equal 'GetRubyIndent()', @editor.settings.get(:indentexpr)
  end
end
