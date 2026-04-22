# frozen_string_literal: true

require_relative 'test_helper'

class TestCscoperelativeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:cscoperelative)
  end

  def test_csre_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csre'))
    assert_equal true, @editor.settings.get(:cscoperelative)
  end
end

class TestCscopepathcompStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:cscopepathcomp)
  end

  def test_cspc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cspc=3'))
    assert_equal 3, @editor.settings.get(:cscopepathcomp)
  end
end

class TestCscopequickfixStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:cscopequickfix)
  end

  def test_csqf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csqf=s-,c-'))
    assert_equal 's-,c-', @editor.settings.get(:cscopequickfix)
  end
end

class TestCscopeverboseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:cscopeverbose)
  end

  def test_csverb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csverb'))
    assert_equal true, @editor.settings.get(:cscopeverbose)
  end
end

class TestTtimeoutStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:ttimeout)
  end

  def test_set_nottimeout
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nottimeout'))
    assert_equal false, @editor.settings.get(:ttimeout)
  end
end
