# frozen_string_literal: true

require_relative 'test_helper'

class TestErrorbellsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:errorbells)
  end

  def test_eb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set eb'))
    assert_equal true, @editor.settings.get(:errorbells)
  end
end

class TestVisualbellStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:visualbell)
  end

  def test_vb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set vb'))
    assert_equal true, @editor.settings.get(:visualbell)
  end
end

class TestTtyfastStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:ttyfast)
  end

  def test_tf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notf'))
    assert_equal false, @editor.settings.get(:ttyfast)
  end
end

class TestTermguicolorsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:termguicolors)
  end

  def test_tgc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tgc'))
    assert_equal true, @editor.settings.get(:termguicolors)
  end
end

class TestTermencodingStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:termencoding)
  end

  def test_tenc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tenc=utf-8'))
    assert_equal 'utf-8', @editor.settings.get(:termencoding)
  end
end
