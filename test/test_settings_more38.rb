# frozen_string_literal: true

require_relative 'test_helper'

class TestCasemapStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_internal
    assert_match(/internal/, @editor.settings.get(:casemap))
  end

  def test_cmp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cmp=internal'))
    assert_equal 'internal', @editor.settings.get(:casemap)
  end
end

class TestQuoteescapeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_backslash
    assert_equal '\\', @editor.settings.get(:quoteescape)
  end

  def test_qe_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set qe=\\\\^'))
    refute_nil @editor.settings.get(:quoteescape)
  end
end

class TestFormatlistpatStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_numbered
    assert_match(/\\d/, @editor.settings.get(:formatlistpat))
  end

  def test_flp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set flp=^*\\\\s'))
    assert_match(/\*/, @editor.settings.get(:formatlistpat))
  end
end

class TestKeymapStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:keymap)
  end

  def test_kmp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set kmp=accents'))
    assert_equal 'accents', @editor.settings.get(:keymap)
  end
end

class TestWinaltkeysStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_menu
    assert_equal 'menu', @editor.settings.get(:winaltkeys)
  end

  def test_wak_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wak=no'))
    assert_equal 'no', @editor.settings.get(:winaltkeys)
  end
end
