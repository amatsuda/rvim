# frozen_string_literal: true

require_relative 'test_helper'

class TestEadirection < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    buf = Rvim::Buffer.new(1, nil)
    @editor.instance_variable_set(:@current_buffer, buf)
    @initial = Rvim::Window.new(buf)
    @initial.extra_rows = 5
    @initial.extra_cols = 7
    @editor.instance_variable_set(:@windows, [@initial])
    @editor.instance_variable_set(:@current_window, @initial)
  end

  def test_default_both_zeros_extras
    @editor.settings.set(:eadirection, 'both')
    @editor.equalize_windows
    assert_equal 0, @initial.extra_rows
    assert_equal 0, @initial.extra_cols
  end

  def test_hor_only_zeros_rows
    @editor.settings.set(:eadirection, 'hor')
    @editor.equalize_windows
    assert_equal 0, @initial.extra_rows
    assert_equal 7, @initial.extra_cols
  end

  def test_ver_only_zeros_cols
    @editor.settings.set(:eadirection, 'ver')
    @editor.equalize_windows
    assert_equal 5, @initial.extra_rows
    assert_equal 0, @initial.extra_cols
  end

  def test_ead_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ead=hor'))
    assert_equal 'hor', @editor.settings.get(:eadirection)
  end
end

class TestWinminheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one
    assert_equal 1, @editor.settings.get(:winminheight)
  end

  def test_wmh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wmh=0'))
    assert_equal 0, @editor.settings.get(:winminheight)
  end
end

class TestWinheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one
    assert_equal 1, @editor.settings.get(:winheight)
  end

  def test_wh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wh=10'))
    assert_equal 10, @editor.settings.get(:winheight)
  end
end

class TestWinwidthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_twenty
    assert_equal 20, @editor.settings.get(:winwidth)
  end

  def test_wiw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wiw=40'))
    assert_equal 40, @editor.settings.get(:winwidth)
  end
end

class TestWinminwidthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_one
    assert_equal 1, @editor.settings.get(:winminwidth)
  end

  def test_wmw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wmw=0'))
    assert_equal 0, @editor.settings.get(:winminwidth)
  end
end

class TestScrollbindStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:scrollbind)
  end

  def test_scb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set scb'))
    assert_equal true, @editor.settings.get(:scrollbind)
  end
end

class TestCursorbindStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:cursorbind)
  end

  def test_crb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set crb'))
    assert_equal true, @editor.settings.get(:cursorbind)
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

class TestWinfixheightStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:winfixheight)
  end

  def test_wfh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wfh'))
    assert_equal true, @editor.settings.get(:winfixheight)
  end
end

class TestWinfixwidthStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:winfixwidth)
  end

  def test_wfw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wfw'))
    assert_equal true, @editor.settings.get(:winfixwidth)
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

class TestSplitDirection < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    buf = Rvim::Buffer.new(1, nil)
    @editor.instance_variable_set(:@current_buffer, buf)
    @initial = Rvim::Window.new(buf)
    @editor.instance_variable_set(:@windows, [@initial])
    @editor.instance_variable_set(:@current_window, @initial)
  end

  def test_default_horizontal_inserts_before_current
    @editor.split_horizontal
    # default splitbelow=false → new split goes BEFORE the current
    assert_equal @editor.windows.first, @editor.current_window
    assert_equal @initial, @editor.windows.last
  end

  def test_splitbelow_inserts_after_current
    @editor.settings.set(:splitbelow, true)
    @editor.split_horizontal
    assert_equal @initial, @editor.windows.first
    assert_equal @editor.current_window, @editor.windows.last
  end

  def test_default_vertical_inserts_before_current
    @editor.split_vertical
    assert_equal @editor.current_window, @editor.windows.first
    assert_equal @initial, @editor.windows.last
  end

  def test_splitright_inserts_after_current
    @editor.settings.set(:splitright, true)
    @editor.split_vertical
    assert_equal @initial, @editor.windows.first
    assert_equal @editor.current_window, @editor.windows.last
  end
end

class TestSplitkeepStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_cursor
    assert_equal 'cursor', @editor.settings.get(:splitkeep)
  end

  def test_spk_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set spk=screen'))
    assert_equal 'screen', @editor.settings.get(:splitkeep)
  end
end

class TestTabpagemaxStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_fifty
    assert_equal 50, @editor.settings.get(:tabpagemax)
  end

  def test_tpm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tpm=10'))
    assert_equal 10, @editor.settings.get(:tabpagemax)
  end
end

class TestEqualalways < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    buf = Rvim::Buffer.new(1, nil)
    @editor.instance_variable_set(:@current_buffer, buf)
    initial = Rvim::Window.new(buf)
    initial.extra_rows = 5
    @editor.instance_variable_set(:@windows, [initial])
    @editor.instance_variable_set(:@current_window, initial)
  end

  def test_default_equalalways_resets_extras_on_split
    @editor.settings.set(:equalalways, true)
    @editor.split_horizontal
    @editor.windows.each { |w| assert_equal 0, w.extra_rows }
  end

  def test_equalalways_off_keeps_extras
    @editor.settings.set(:equalalways, false)
    @editor.split_horizontal
    # Initial window's extra_rows should still be 5
    assert_equal 5, @editor.windows.find { |w| w != @editor.current_window }.extra_rows
  end
end

class TestWinblendStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:winblend)
  end

  def test_winbl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set winbl=20'))
    assert_equal 20, @editor.settings.get(:winblend)
  end
end
