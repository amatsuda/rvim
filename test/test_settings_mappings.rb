# frozen_string_literal: true

require_relative 'test_helper'

class TestWildignore < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:wildignore)
  end

  def test_wig_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wig=*.o,*.obj'))
    assert_equal '*.o,*.obj', @editor.settings.get(:wildignore)
  end

  def test_filters_files_by_pattern
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'main.c'), '')
      File.write(File.join(dir, 'main.o'), '')
      File.write(File.join(dir, 'lib.o'), '')
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.settings.set(:wildignore, '*.o')
      ctx = Rvim::CmdlineCompletion::Context.new(kind: :filename, partial: '', prefix: 'e ')
      out = Rvim::CmdlineCompletion.candidates(ctx, @editor)
      assert out.include?('main.c')
      refute out.include?('main.o')
      refute out.include?('lib.o')
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_no_patterns_means_no_filter
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'main.o'), '')
      saved = Dir.pwd
      Dir.chdir(dir)
      ctx = Rvim::CmdlineCompletion::Context.new(kind: :filename, partial: '', prefix: 'e ')
      out = Rvim::CmdlineCompletion.candidates(ctx, @editor)
      assert out.include?('main.o')
    ensure
      Dir.chdir(saved) if saved
    end
  end
end

class TestTimeoutSettings < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_timeout_default_on
    assert_equal true, @editor.settings.get(:timeout)
  end

  def test_to_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notimeout'))
    assert_equal false, @editor.settings.get(:timeout)
  end

  def test_timeoutlen_default
    assert_equal 1000, @editor.settings.get(:timeoutlen)
  end

  def test_tm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tm=500'))
    assert_equal 500, @editor.settings.get(:timeoutlen)
  end

  def test_ttimeoutlen_default_minus_one
    assert_equal(-1, @editor.settings.get(:ttimeoutlen))
  end

  def test_set_ttimeoutlen
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ttimeoutlen=50'))
    assert_equal 50, @editor.settings.get(:ttimeoutlen)
  end
end

class TestLangmapStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:langmap)
  end

  def test_lmap_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lmap=jk;hl'))
    assert_equal 'jk;hl', @editor.settings.get(:langmap)
  end
end

class TestLangremapStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:langremap)
  end

  def test_set_langremap
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set langremap'))
    assert_equal true, @editor.settings.get(:langremap)
  end
end

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

class TestWildoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:wildoptions)
  end

  def test_wop_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wop=tagfile'))
    assert_equal 'tagfile', @editor.settings.get(:wildoptions)
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

class TestWildignorecaseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:wildignorecase)
  end

  def test_wic_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wic'))
    assert_equal true, @editor.settings.get(:wildignorecase)
  end
end

class TestTtimeoutStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:ttimeout)
  end

  def test_set_nottimeout
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nottimeout'))
    assert_equal false, @editor.settings.get(:ttimeout)
  end
end

class TestLangnoremapStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:langnoremap)
  end

  def test_set_nolangnoremap
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nolangnoremap'))
    assert_equal false, @editor.settings.get(:langnoremap)
  end
end

class TestLangmenuStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:langmenu)
  end

  def test_lm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set lm=ja_JP'))
    assert_equal 'ja_JP', @editor.settings.get(:langmenu)
  end
end
