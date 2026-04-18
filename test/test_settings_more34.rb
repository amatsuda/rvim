# frozen_string_literal: true

require_relative 'test_helper'

class TestWildcharStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_tab
    assert_equal 9, @editor.settings.get(:wildchar)
  end

  def test_wc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wc=27'))
    assert_equal 27, @editor.settings.get(:wildchar)
  end
end

class TestWildcharmStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:wildcharm)
  end

  def test_wcm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wcm=9'))
    assert_equal 9, @editor.settings.get(:wildcharm)
  end
end

class TestWildmodeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_full
    assert_equal 'full', @editor.settings.get(:wildmode)
  end

  def test_wim_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wim=longest:full,full'))
    assert_equal 'longest:full,full', @editor.settings.get(:wildmode)
  end
end

class TestPreviewheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_twelve
    assert_equal 12, @editor.settings.get(:previewheight)
  end

  def test_pvh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pvh=20'))
    assert_equal 20, @editor.settings.get(:previewheight)
  end
end

class TestJoinspacesStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:joinspaces)
  end

  def test_js_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nojoinspaces'))
    assert_equal false, @editor.settings.get(:joinspaces)
  end
end
