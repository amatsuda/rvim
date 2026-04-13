# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestShellcmdflag < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_minus_c
    assert_equal '-c', @editor.settings.get(:shellcmdflag)
  end

  def test_shcf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set shcf=-x'))
    assert_equal '-x', @editor.settings.get(:shellcmdflag)
  end

  def test_filter_run_uses_default_minus_c
    out = Rvim::Filter.run('echo hello')
    assert_equal "hello\n", out.stdout
  end

  def test_filter_run_with_explicit_flag
    # Custom shell flag — sh -c is the standard so this just confirms threading
    out = Rvim::Filter.run('echo hi', shellcmdflag: '-c')
    assert_equal "hi\n", out.stdout
  end

  def test_filter_run_empty_flag_falls_back
    out = Rvim::Filter.run('echo fallback', shellcmdflag: '')
    assert_equal "fallback\n", out.stdout
  end
end

class TestGrepformat < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_format_present
    assert_match(/%f:%l/, @editor.settings.get(:grepformat))
  end

  def test_gfm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set gfm=%f-%l-%m'))
    assert_equal '%f-%l-%m', @editor.settings.get(:grepformat)
  end

  def test_grep_uses_grepformat_when_set
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "TODO: x\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      # Switch grepprg to produce a non-standard format
      @editor.settings.set(:grepprg, "awk -F: '{print $1\"|\"$2\"|\"$3}' /dev/null")
      # ... actually that's complex; simpler: keep grepprg default but change
      # grepformat to be incompatible and confirm zero matches.
      @editor.settings.set(:grepprg, 'grep -n $* /dev/null')
      @editor.settings.set(:grepformat, '%f:NONE:%m')
      Rvim::Command.execute(@editor, Rvim::Command.parse(':grep! TODO *.rb'))
      # grepformat doesn't match grep's output → zero entries
      assert_equal 0, @editor.quickfix.size
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_grep_falls_back_to_errorformat_when_gfm_empty
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "TODO: hit\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.settings.set(:grepformat, '')
      Rvim::Command.execute(@editor, Rvim::Command.parse(':grep! TODO *.rb'))
      assert_equal 1, @editor.quickfix.size
    ensure
      Dir.chdir(saved) if saved
    end
  end
end

class TestBelloff < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_all
    assert_equal 'all', @editor.settings.get(:belloff)
  end

  def test_bo_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set bo=esc'))
    assert_equal 'esc', @editor.settings.get(:belloff)
  end
end
