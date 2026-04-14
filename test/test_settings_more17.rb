# frozen_string_literal: true

require_relative 'test_helper'

class TestSigncolumn < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
  end

  def test_default_auto
    assert_equal 'auto', @editor.settings.get(:signcolumn)
  end

  def test_scl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set scl=yes'))
    assert_equal 'yes', @editor.settings.get(:signcolumn)
  end

  def test_auto_zero_extra_width
    @editor.settings.set(:signcolumn, 'auto')
    assert_equal 0, @screen.send(:sign_column_width)
  end

  def test_yes_reserves_two_columns
    @editor.settings.set(:signcolumn, 'yes')
    assert_equal 2, @screen.send(:sign_column_width)
  end

  def test_no_zero_columns
    @editor.settings.set(:signcolumn, 'no')
    assert_equal 0, @screen.send(:sign_column_width)
  end

  def test_gutter_width_includes_sign_column
    @editor.settings.set(:number, true)
    @editor.settings.set(:numberwidth, 4)
    @editor.settings.set(:signcolumn, 'yes')
    buf = Rvim::Buffer.new(1, nil); buf.lines = (1..10).map(&:to_s)
    width = @screen.send(:gutter_width, buf)
    assert_equal 4 + 2, width # numberwidth + sign column
  end

  def test_gutter_width_only_signs
    @editor.settings.set(:number, false)
    @editor.settings.set(:relativenumber, false)
    @editor.settings.set(:signcolumn, 'yes')
    buf = Rvim::Buffer.new(1, nil); buf.lines = ['a']
    assert_equal 2, @screen.send(:gutter_width, buf)
  end
end

class TestUpdatetimeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_4000
    assert_equal 4000, @editor.settings.get(:updatetime)
  end

  def test_ut_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ut=200'))
    assert_equal 200, @editor.settings.get(:updatetime)
  end
end

class TestShortmessStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_value
    assert_equal 'filnxtToOS', @editor.settings.get(:shortmess)
  end

  def test_shm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set shm=at'))
    assert_equal 'at', @editor.settings.get(:shortmess)
  end
end
