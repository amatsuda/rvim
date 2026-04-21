# frozen_string_literal: true

require_relative 'test_helper'

class TestWriteStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:write)
  end

  def test_set_nowrite
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nowrite'))
    assert_equal false, @editor.settings.get(:write)
  end
end

class TestWriteanyStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:writeany)
  end

  def test_wa_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wa'))
    assert_equal true, @editor.settings.get(:writeany)
  end
end

class TestWritedelayStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:writedelay)
  end

  def test_wd_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wd=100'))
    assert_equal 100, @editor.settings.get(:writedelay)
  end
end

class TestAutowriteallStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:autowriteall)
  end

  def test_awa_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set awa'))
    assert_equal true, @editor.settings.get(:autowriteall)
  end
end

class TestFsyncStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:fsync)
  end

  def test_fs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fs'))
    assert_equal true, @editor.settings.get(:fsync)
  end
end
