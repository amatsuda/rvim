# frozen_string_literal: true

require_relative 'test_helper'

class TestSidescrollStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:sidescroll)
  end

  def test_ss_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ss=10'))
    assert_equal 10, @editor.settings.get(:sidescroll)
  end
end

class TestPumwidthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_fifteen
    assert_equal 15, @editor.settings.get(:pumwidth)
  end

  def test_pw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pw=30'))
    assert_equal 30, @editor.settings.get(:pumwidth)
  end
end

class TestSplitkeepStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_cursor
    assert_equal 'cursor', @editor.settings.get(:splitkeep)
  end

  def test_spk_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set spk=screen'))
    assert_equal 'screen', @editor.settings.get(:splitkeep)
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
