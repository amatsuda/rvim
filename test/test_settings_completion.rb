# frozen_string_literal: true

require_relative 'test_helper'

class TestCompleteopt < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def test_default_menu
    assert_equal 'menu', @editor.settings.get(:completeopt)
  end

  def test_cot_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cot=menu,noinsert'))
    assert_equal 'menu,noinsert', @editor.settings.get(:completeopt)
  end

  def test_default_replaces_base_with_first_candidate
    @editor.instance_variable_set(:@buffer_of_lines, ['hello hero help'.dup, 'he'.dup])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.send(:start_completion, +1)
    assert_equal 'hello', @editor.buffer_of_lines[1]
  end

  def test_noinsert_keeps_base_text
    @editor.settings.set(:completeopt, 'menu,noinsert')
    @editor.instance_variable_set(:@buffer_of_lines, ['hello hero help'.dup, 'he'.dup])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.send(:start_completion, +1)
    # Buffer text unchanged; popup is still active so user can pick
    assert_equal 'he', @editor.buffer_of_lines[1]
    assert_equal true, @editor.completion_active
    refute_nil @editor.completion_popup
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

class TestOmnifuncStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:omnifunc)
  end

  def test_ofu_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ofu=MyOmni'))
    assert_equal 'MyOmni', @editor.settings.get(:omnifunc)
  end
end

class TestOperatorfuncStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:operatorfunc)
  end

  def test_opfunc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set opfunc=MyOp'))
    assert_equal 'MyOp', @editor.settings.get(:operatorfunc)
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

class TestPumblendStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:pumblend)
  end

  def test_set_pumblend
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pumblend=15'))
    assert_equal 15, @editor.settings.get(:pumblend)
  end
end

class TestPumheight < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def test_default_is_zero_meaning_use_struct_default
    assert_equal 0, @editor.settings.get(:pumheight)
  end

  def test_ph_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ph=3'))
    assert_equal 3, @editor.settings.get(:pumheight)
  end

  def test_completion_popup_uses_pumheight_when_set
    @editor.settings.set(:pumheight, 3)
    @editor.instance_variable_set(:@buffer_of_lines, ['hello hero help happy hi'.dup, 'he'.dup])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.send(:start_completion, +1)
    assert_equal 3, @editor.completion_popup.max_height
  end

  def test_completion_popup_uses_struct_default_when_zero
    @editor.settings.set(:pumheight, 0)
    @editor.instance_variable_set(:@buffer_of_lines, ['hello hero help'.dup, 'he'.dup])
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 2)
    @editor.send(:start_completion, +1)
    assert_equal Rvim::CompletionPopup::DEFAULT_MAX_HEIGHT, @editor.completion_popup.max_height
  end
end
