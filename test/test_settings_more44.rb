# frozen_string_literal: true

require_relative 'test_helper'

class TestMaxmemStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one_gib
    assert_equal 1_048_576, @editor.settings.get(:maxmem)
  end

  def test_mm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mm=2000000'))
    assert_equal 2_000_000, @editor.settings.get(:maxmem)
  end
end

class TestMaxmempatternStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one_thousand
    assert_equal 1000, @editor.settings.get(:maxmempattern)
  end

  def test_mmp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mmp=5000'))
    assert_equal 5000, @editor.settings.get(:maxmempattern)
  end
end

class TestMaxmemtotStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default
    assert_equal 1_048_576, @editor.settings.get(:maxmemtot)
  end

  def test_mmt_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mmt=2097152'))
    assert_equal 2_097_152, @editor.settings.get(:maxmemtot)
  end
end

class TestMaxmapdepthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one_thousand
    assert_equal 1000, @editor.settings.get(:maxmapdepth)
  end

  def test_mmd_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mmd=200'))
    assert_equal 200, @editor.settings.get(:maxmapdepth)
  end
end

class TestMaxfuncdepthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one_hundred
    assert_equal 100, @editor.settings.get(:maxfuncdepth)
  end

  def test_mfd_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mfd=50'))
    assert_equal 50, @editor.settings.get(:maxfuncdepth)
  end
end
