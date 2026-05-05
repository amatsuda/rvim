# frozen_string_literal: true

require_relative 'test_helper'

class TestShellSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_bin_sh
    assert_equal '/bin/sh', @editor.settings.get(:shell)
  end

  def test_filter_run_uses_default_shell
    out = Rvim::Filter.run('echo hi')
    assert_equal "hi\n", out.stdout
  end

  def test_filter_run_with_custom_shell
    # Use a shell that's definitely on the system
    out = Rvim::Filter.run('echo hello', shell: '/bin/sh')
    assert_equal "hello\n", out.stdout
  end

  def test_filter_command_uses_settings_shell
    @editor.settings.set(:shell, '/bin/sh')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!echo from_setting'))
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/from_setting/, body)
  end

  def test_sh_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sh=/bin/bash'))
    assert_equal '/bin/bash', @editor.settings.get(:shell)
  end
end

class TestFormatprg < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:formatprg)
  end

  def test_fp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fp=fmt'))
    assert_equal 'fmt', @editor.settings.get(:formatprg)
  end

  def test_format_uses_formatprg_when_set
    @editor.instance_variable_set(:@buffer_of_lines, [+'banana', +'apple', +'cherry'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:formatprg, 'sort')
    @editor.apply_format_to_lines(0, 2)
    assert_equal %w[apple banana cherry], @editor.buffer_of_lines
  end

  def test_format_falls_back_to_internal_reformat_when_empty
    @editor.settings.set(:textwidth, 12)
    @editor.settings.set(:formatprg, '')
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello world how are you'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.apply_format_to_lines(0, 0)
    assert @editor.buffer_of_lines.size > 1
  end

  def test_format_failure_keeps_buffer
    @editor.instance_variable_set(:@buffer_of_lines, [+'a', +'b', +'c'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:formatprg, 'false')
    @editor.apply_format_to_lines(0, 2)
    assert_equal %w[a b c], @editor.buffer_of_lines
    assert_match(/formatprg/, @editor.status_message.to_s)
  end
end

class TestEqualOperator < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def fire_equal
    @editor.send(:rvim_equal_operator, nil)
  end

  def test_default_equalprg_empty_no_op
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    fire_equal
    @editor.update(k('='))
    assert_equal 'hello', @editor.buffer_of_lines[0] # unchanged
  end

  def test_equal_equal_runs_equalprg_on_current_line
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:equalprg, 'tr a-z A-Z')
    fire_equal
    @editor.update(k('='))
    assert_equal 'HELLO', @editor.buffer_of_lines[0]
  end

  def test_equal_with_motion_runs_on_range
    @editor.instance_variable_set(:@buffer_of_lines, [+'one', +'two', +'three'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:equalprg, 'tr a-z A-Z')
    fire_equal
    @editor.update(k('j'))
    # Motion j → line range 0..1 piped through tr
    assert_equal 'ONE', @editor.buffer_of_lines[0]
    assert_equal 'TWO', @editor.buffer_of_lines[1]
    assert_equal 'three', @editor.buffer_of_lines[2]
  end

  def test_equalprg_failure_keeps_buffer
    @editor.instance_variable_set(:@buffer_of_lines, [+'a', +'b'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.settings.set(:equalprg, 'false')
    fire_equal
    @editor.update(k('='))
    assert_equal %w[a b], @editor.buffer_of_lines
    assert_match(/equalprg/, @editor.status_message.to_s)
  end

  def test_ep_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ep=indent'))
    assert_equal 'indent', @editor.settings.get(:equalprg)
  end
end

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

class TestShellpipeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_tee
    assert_match(/tee/, @editor.settings.get(:shellpipe))
  end

  def test_sp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sp=>%s'))
    assert_equal '>%s', @editor.settings.get(:shellpipe)
  end
end

class TestShellredirStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_redirect
    assert_equal '>%s 2>&1', @editor.settings.get(:shellredir)
  end

  def test_srr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set srr=>'))
    assert_equal '>', @editor.settings.get(:shellredir)
  end
end

class TestShellslashStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:shellslash)
  end

  def test_ssl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ssl'))
    assert_equal true, @editor.settings.get(:shellslash)
  end
end

class TestCscopetagStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:cscopetag)
  end

  def test_cst_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cst'))
    assert_equal true, @editor.settings.get(:cscopetag)
  end
end

class TestCscopeprgStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_cscope
    assert_equal 'cscope', @editor.settings.get(:cscopeprg)
  end

  def test_csprg_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csprg=/usr/local/bin/cscope'))
    assert_equal '/usr/local/bin/cscope', @editor.settings.get(:cscopeprg)
  end
end

class TestCscopetagorderStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:cscopetagorder)
  end

  def test_csto_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csto=1'))
    assert_equal 1, @editor.settings.get(:cscopetagorder)
  end
end

class TestPrintheaderStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_default
    assert_match(/Page/, @editor.settings.get(:printheader))
  end

  def test_pheader_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pheader=%f'))
    assert_equal '%f', @editor.settings.get(:printheader)
  end
end

class TestPrintoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:printoptions)
  end

  def test_popt_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set popt=duplex:long'))
    assert_equal 'duplex:long', @editor.settings.get(:printoptions)
  end
end

class TestPrintfontStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_courier
    assert_equal 'courier', @editor.settings.get(:printfont)
  end

  def test_pfn_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pfn=monaco:h10'))
    assert_equal 'monaco:h10', @editor.settings.get(:printfont)
  end
end

class TestPrintencodingStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:printencoding)
  end

  def test_penc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set penc=utf-8'))
    assert_equal 'utf-8', @editor.settings.get(:printencoding)
  end
end

class TestPrintexprStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:printexpr)
  end

  def test_pexpr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pexpr=system(...)'))
    assert_equal 'system(...)', @editor.settings.get(:printexpr)
  end
end

class TestCscoperelativeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:cscoperelative)
  end

  def test_csre_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csre'))
    assert_equal true, @editor.settings.get(:cscoperelative)
  end
end

class TestCscopepathcompStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:cscopepathcomp)
  end

  def test_cspc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cspc=3'))
    assert_equal 3, @editor.settings.get(:cscopepathcomp)
  end
end

class TestCscopequickfixStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:cscopequickfix)
  end

  def test_csqf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csqf=s-,c-'))
    assert_equal 's-,c-', @editor.settings.get(:cscopequickfix)
  end
end

class TestCscopeverboseStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:cscopeverbose)
  end

  def test_csverb_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set csverb'))
    assert_equal true, @editor.settings.get(:cscopeverbose)
  end
end

class TestKeywordprg < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def test_default_is_man
    assert_equal 'man', @editor.settings.get(:keywordprg)
  end

  def test_kp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set kp=help'))
    assert_equal 'help', @editor.settings.get(:keywordprg)
  end

  def test_K_uses_keywordprg
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello world'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    # Use 'echo' as keywordprg so it always succeeds and is portable
    @editor.settings.set(:keywordprg, 'echo')
    @editor.send(:rvim_keyword_lookup, nil)
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/hello/, body)
  end

  def test_K_with_no_word_sets_status
    @editor.instance_variable_set(:@buffer_of_lines, [+'   '])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:rvim_keyword_lookup, nil)
    assert_match(/E348/, @editor.status_message.to_s)
  end

  def test_K_with_failing_program
    @editor.instance_variable_set(:@buffer_of_lines, [+'word'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.settings.set(:keywordprg, 'false')
    @editor.send(:rvim_keyword_lookup, nil)
    assert_match(/^K:/, @editor.status_message.to_s)
  end
end
