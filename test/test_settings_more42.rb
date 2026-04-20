# frozen_string_literal: true

require_relative 'test_helper'

class TestSpellcapcheckStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_sentence_pattern
    assert_match(/\?\!/, @editor.settings.get(:spellcapcheck))
  end

  def test_spc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set spc=[.!?]'))
    assert_equal '[.!?]', @editor.settings.get(:spellcapcheck)
  end
end

class TestSpellfileStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:spellfile)
  end

  def test_spf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set spf=~/.cache/spell/en.utf-8.add'))
    assert_equal '~/.cache/spell/en.utf-8.add', @editor.settings.get(:spellfile)
  end
end

class TestSpellsuggestStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_best
    assert_equal 'best', @editor.settings.get(:spellsuggest)
  end

  def test_sps_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sps=double,5'))
    assert_equal 'double,5', @editor.settings.get(:spellsuggest)
  end
end

class TestSpelloptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:spelloptions)
  end

  def test_set_spelloptions
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set spelloptions=camel'))
    assert_equal 'camel', @editor.settings.get(:spelloptions)
  end
end

class TestDigraphStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:digraph)
  end

  def test_dg_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set dg'))
    assert_equal true, @editor.settings.get(:digraph)
  end
end
