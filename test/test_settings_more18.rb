# frozen_string_literal: true

require_relative 'test_helper'

class TestClipboardSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:clipboard)
  end

  def test_cb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cb=unnamedplus'))
    assert_equal 'unnamedplus', @editor.settings.get(:clipboard)
  end

  def stub_clipboard
    written = []
    original = Rvim::SystemClipboard.method(:write)
    Rvim::SystemClipboard.define_singleton_method(:write) { |s| written << s }
    yield written
  ensure
    Rvim::SystemClipboard.define_singleton_method(:write, &original)
  end

  def test_unnamedplus_mirrors_unnamed_yank_to_system_clipboard
    @editor.settings.set(:clipboard, 'unnamedplus')
    stub_clipboard do |written|
      @editor.write_register('hello', :char)
      assert_equal ['hello'], written
    end
  end

  def test_no_clipboard_setting_does_not_mirror
    stub_clipboard do |written|
      @editor.write_register('hello', :char)
      assert_equal [], written
    end
  end
end

class TestBackgroundStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_dark
    assert_equal 'dark', @editor.settings.get(:background)
  end

  def test_bg_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set bg=light'))
    assert_equal 'light', @editor.settings.get(:background)
  end
end

class TestSwitchbufStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_uselast
    assert_equal 'uselast', @editor.settings.get(:switchbuf)
  end

  def test_swb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set swb=useopen,split'))
    assert_equal 'useopen,split', @editor.settings.get(:switchbuf)
  end
end
