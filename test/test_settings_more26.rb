# frozen_string_literal: true

require_relative 'test_helper'

class TestConceallevelStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:conceallevel)
  end

  def test_cole_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cole=2'))
    assert_equal 2, @editor.settings.get(:conceallevel)
  end
end

class TestConcealcursorStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:concealcursor)
  end

  def test_cocu_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cocu=nv'))
    assert_equal 'nv', @editor.settings.get(:concealcursor)
  end
end

class TestBreakatStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_punct
    assert_match(/[!@*]/, @editor.settings.get(:breakat))
  end

  def test_brk_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set brk=\ \t-'))
    refute_nil @editor.settings.get(:breakat)
  end
end

class TestMatchtimeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_five
    assert_equal 5, @editor.settings.get(:matchtime)
  end

  def test_mat_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mat=10'))
    assert_equal 10, @editor.settings.get(:matchtime)
  end
end

class TestCmdwinheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_seven
    assert_equal 7, @editor.settings.get(:cmdwinheight)
  end

  def test_cwh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cwh=10'))
    assert_equal 10, @editor.settings.get(:cmdwinheight)
  end
end
