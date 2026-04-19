# frozen_string_literal: true

require_relative 'test_helper'

class TestViminfoStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_default_string
    assert_match(/100/, @editor.settings.get(:viminfo))
  end

  def test_vi_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(":set vi='200,h"))
    assert_equal "'200,h", @editor.settings.get(:viminfo)
  end
end

class TestCompleteStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_sources
    assert_equal '.,w,b,u,t', @editor.settings.get(:complete)
  end

  def test_cpt_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cpt=.,k'))
    assert_equal '.,k', @editor.settings.get(:complete)
  end
end

class TestDictionaryStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:dictionary)
  end

  def test_dict_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set dict=/usr/share/dict/words'))
    assert_equal '/usr/share/dict/words', @editor.settings.get(:dictionary)
  end
end

class TestThesaurusStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:thesaurus)
  end

  def test_tsr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tsr=/usr/share/thesaurus.txt'))
    assert_equal '/usr/share/thesaurus.txt', @editor.settings.get(:thesaurus)
  end
end

class TestGdefaultStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:gdefault)
  end

  def test_gd_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set gd'))
    assert_equal true, @editor.settings.get(:gdefault)
  end
end
