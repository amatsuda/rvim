# frozen_string_literal: true

require_relative 'test_helper'

class TestSecureStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:secure)
  end

  def test_set_secure
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set secure'))
    assert_equal true, @editor.settings.get(:secure)
  end
end

class TestExrcStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:exrc)
  end

  def test_ex_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set exrc'))
    assert_equal true, @editor.settings.get(:exrc)
  end
end

class TestMoreStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:more)
  end

  def test_set_nomore
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nomore'))
    assert_equal false, @editor.settings.get(:more)
  end
end

class TestCeditStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_ctrl_f
    assert_equal "\x06", @editor.settings.get(:cedit)
  end

  def test_set_cedit
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cedit=^E'))
    assert_equal '^E', @editor.settings.get(:cedit)
  end
end

class TestWildoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:wildoptions)
  end

  def test_wop_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wop=tagfile'))
    assert_equal 'tagfile', @editor.settings.get(:wildoptions)
  end
end
