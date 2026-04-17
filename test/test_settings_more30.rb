# frozen_string_literal: true

require_relative 'test_helper'

class TestScrollbindStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:scrollbind)
  end

  def test_scb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set scb'))
    assert_equal true, @editor.settings.get(:scrollbind)
  end
end

class TestCursorbindStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:cursorbind)
  end

  def test_crb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set crb'))
    assert_equal true, @editor.settings.get(:cursorbind)
  end
end

class TestShellpipeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_tee
    assert_match(/tee/, @editor.settings.get(:shellpipe))
  end

  def test_sp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sp=>%s'))
    assert_equal '>%s', @editor.settings.get(:shellpipe)
  end
end

class TestShellredirStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_redirect
    assert_equal '>%s 2>&1', @editor.settings.get(:shellredir)
  end

  def test_srr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set srr=>'))
    assert_equal '>', @editor.settings.get(:shellredir)
  end
end

class TestShellslashStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:shellslash)
  end

  def test_ssl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ssl'))
    assert_equal true, @editor.settings.get(:shellslash)
  end
end
