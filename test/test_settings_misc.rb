# frozen_string_literal: true

require_relative 'test_helper'

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

class TestSynmaxcolStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_three_thousand
    assert_equal 3000, @editor.settings.get(:synmaxcol)
  end

  def test_smc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set smc=200'))
    assert_equal 200, @editor.settings.get(:synmaxcol)
  end
end

class TestRedrawtimeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_two_thousand
    assert_equal 2000, @editor.settings.get(:redrawtime)
  end

  def test_rdt_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set rdt=500'))
    assert_equal 500, @editor.settings.get(:redrawtime)
  end
end

class TestMatchtimeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_five
    assert_equal 5, @editor.settings.get(:matchtime)
  end

  def test_mat_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mat=10'))
    assert_equal 10, @editor.settings.get(:matchtime)
  end
end

class TestCpoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_vim_compat_flags
    assert_equal 'aABceFs', @editor.settings.get(:cpoptions)
  end

  def test_cpo_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cpo=aB'))
    assert_equal 'aB', @editor.settings.get(:cpoptions)
  end
end

class TestSecureStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:secure)
  end

  def test_set_secure
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set secure'))
    assert_equal true, @editor.settings.get(:secure)
  end
end

class TestExrcStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:exrc)
  end

  def test_ex_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set exrc'))
    assert_equal true, @editor.settings.get(:exrc)
  end
end

class TestMoreStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:more)
  end

  def test_set_nomore
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nomore'))
    assert_equal false, @editor.settings.get(:more)
  end
end

class TestCeditStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_ctrl_f
    assert_equal "\x06", @editor.settings.get(:cedit)
  end

  def test_set_cedit
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cedit=^E'))
    assert_equal '^E', @editor.settings.get(:cedit)
  end
end

class TestSettingAliases < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_aliases_via_set
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set spr'))
    assert_equal true, @editor.settings.get(:splitright)

    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sb'))
    assert_equal true, @editor.settings.get(:splitbelow)

    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nosmd'))
    assert_equal false, @editor.settings.get(:showmode)

    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nois'))
    assert_equal false, @editor.settings.get(:incsearch)

    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lz'))
    assert_equal true, @editor.settings.get(:lazyredraw)
  end
end

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

class TestDelcombineStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:delcombine)
  end

  def test_deco_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set deco'))
    assert_equal true, @editor.settings.get(:delcombine)
  end
end

class TestEmojiStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:emoji)
  end

  def test_emo_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set noemoji'))
    assert_equal false, @editor.settings.get(:emoji)
  end
end

class TestTerseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:terse)
  end

  def test_set_terse
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set terse'))
    assert_equal true, @editor.settings.get(:terse)
  end
end

class TestWarnStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:warn)
  end

  def test_set_nowarn
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nowarn'))
    assert_equal false, @editor.settings.get(:warn)
  end
end

class TestHistorySetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_100
    assert_equal 100, @editor.settings.get(:history)
  end

  def test_history_caps_ex_history_size
    @editor.settings.set(:history, 3)
    %w[a b c d e].each { |c| @editor.send(:push_ex_history, c) }
    assert_equal 3, @editor.ex_history.size
    assert_equal %w[c d e], @editor.ex_history
  end

  def test_hi_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set hi=20'))
    assert_equal 20, @editor.settings.get(:history)
  end

  def test_zero_or_negative_falls_back_to_default
    @editor.settings.set(:history, 0)
    50.times { |i| @editor.send(:push_ex_history, i.to_s) }
    # With history=0 we fall back to EX_HISTORY_MAX (100), so all 50 fit
    assert_equal 50, @editor.ex_history.size
  end
end

class TestQuickfixtextfuncStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:quickfixtextfunc)
  end

  def test_qftf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set qftf=MyQfText'))
    assert_equal 'MyQfText', @editor.settings.get(:quickfixtextfunc)
  end
end

class TestInccommandStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_nosplit
    assert_equal 'nosplit', @editor.settings.get(:inccommand)
  end

  def test_icm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set icm=split'))
    assert_equal 'split', @editor.settings.get(:inccommand)
  end
end

class TestRestorescreenStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:restorescreen)
  end

  def test_rs_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nors'))
    assert_equal false, @editor.settings.get(:restorescreen)
  end
end

class TestNrformats < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def buf(line, byte: 0)
    @editor.instance_variable_set(:@buffer_of_lines, [+line])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, byte)
  end

  def increment(arg: 1)
    @editor.send(:rvim_increment, nil, arg: arg)
  end

  def decrement(arg: 1)
    @editor.send(:rvim_decrement, nil, arg: arg)
  end

  def test_hex_increment
    buf('addr 0x1F', byte: 5)
    increment
    assert_equal 'addr 0x20', @editor.buffer_of_lines[0]
  end

  def test_hex_decrement
    buf('addr 0x10', byte: 5)
    decrement
    assert_equal 'addr 0x0f', @editor.buffer_of_lines[0]
  end

  def test_hex_preserves_width
    buf('val 0x0001', byte: 4)
    increment
    assert_equal 'val 0x0002', @editor.buffer_of_lines[0]
  end

  def test_bin_increment
    buf('flag 0b101', byte: 5)
    increment
    assert_equal 'flag 0b110', @editor.buffer_of_lines[0]
  end

  def test_decimal_still_works
    buf('count 42')
    increment
    assert_equal 'count 43', @editor.buffer_of_lines[0]
  end

  def test_disabling_hex_falls_back_to_decimal
    @editor.settings.set(:nrformats, '')
    buf('addr 0x1F', byte: 5)
    increment
    # With nrformats='' cursor on '0' increments it to 1 (treats '0' as decimal)
    assert_equal 'addr 1x1F', @editor.buffer_of_lines[0]
  end

  def test_nf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nf=hex'))
    assert_equal 'hex', @editor.settings.get(:nrformats)
  end
end
