# frozen_string_literal: true

require_relative 'test_helper'

class TestTagcaseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_followic
    assert_equal 'followic', @editor.settings.get(:tagcase)
  end

  def test_tc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tc=match'))
    assert_equal 'match', @editor.settings.get(:tagcase)
  end
end

class TestTagstackStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:tagstack)
  end

  def test_tgst_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notagstack'))
    assert_equal false, @editor.settings.get(:tagstack)
  end
end

class TestTaglengthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:taglength)
  end

  def test_set_taglength
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set taglength=10'))
    assert_equal 10, @editor.settings.get(:taglength)
  end
end

class TestTagrelativeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:tagrelative)
  end

  def test_tr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notagrelative'))
    assert_equal false, @editor.settings.get(:tagrelative)
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

class TestTagbsearchStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:tagbsearch)
  end

  def test_tbs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notbs'))
    assert_equal false, @editor.settings.get(:tagbsearch)
  end
end
