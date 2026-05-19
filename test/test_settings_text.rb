# frozen_string_literal: true

require_relative 'test_helper'

class TestTildeop < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def test_default_off_toggles_single_char
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:rvim_tilde, nil)
    assert_equal 'Hello', @editor.buffer_of_lines[0]
    assert_equal 1, @editor.byte_pointer
  end

  def test_tildeop_on_makes_tilde_an_operator
    @editor.settings.set(:tildeop, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+'hello WORLD'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    @editor.send(:rvim_tilde, nil)
    # tildeop sets pending; next key is the motion
    @editor.update(k('$'))
    assert_equal 'HELLO world', @editor.buffer_of_lines[0]
  end

  def test_top_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set top'))
    assert_equal true, @editor.settings.get(:tildeop)
  end
end

class TestPasteSetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:paste)
  end

  def test_ps_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ps'))
    assert_equal true, @editor.settings.get(:paste)
  end

  def test_pastetoggle_stored
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pt=<F2>'))
    assert_equal '<F2>', @editor.settings.get(:pastetoggle)
  end

  def test_paste_disables_autoindent_on_newline
    @editor.settings.set(:autoindent, true)
    @editor.settings.set(:paste, true)
    @editor.instance_variable_set(:@buffer_of_lines, [+'    indented'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 12)
    @editor.send(:rvim_insert_newline, nil)
    # Paste mode skips the indent carry
    assert_equal ['    indented', ''], @editor.buffer_of_lines
  end

  def test_paste_off_carries_indent
    @editor.settings.set(:autoindent, true)
    @editor.settings.set(:paste, false)
    @editor.instance_variable_set(:@buffer_of_lines, [+'    indented'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 12)
    @editor.send(:rvim_insert_newline, nil)
    assert_equal '    ', @editor.buffer_of_lines[1]
  end
end

class TestInfercase < Test::Unit::TestCase
  def test_default_off
    e = Rvim::Editor.new(Reline.core.config)
    assert_equal false, e.settings.get(:infercase)
  end

  def test_inf_alias
    e = Rvim::Editor.new(Reline.core.config)
    Rvim::Command.execute(e, Rvim::Command.parse(':set inf'))
    assert_equal true, e.settings.get(:infercase)
  end

  def test_candidates_case_sensitive_by_default
    out = Rvim::Completion.candidates(['hello', 'Hello'], 'he')
    assert_equal ['hello'], out
  end

  def test_candidates_infercase_matches_both
    out = Rvim::Completion.candidates(['hello', 'Helsinki'], 'HE', infercase: true)
    # Both 'hello' and 'Helsinki' match (case-insensitive); result candidates
    # are adjusted to the base case ('HE' → uppercase first 2 chars)
    assert_equal 2, out.size
    out.each { |w| assert w.start_with?('HE'), "expected #{w.inspect} to start with HE" }
  end

  def test_candidates_infercase_preserves_rest
    out = Rvim::Completion.candidates(['Hello', 'helsinki'], 'He', infercase: true)
    # First two chars match 'He', rest preserved as-is
    assert out.include?('Hello')
    assert out.include?('Helsinki')
  end

  def test_match_case_to_base_helper
    assert_equal 'HEllo', Rvim::Completion.match_case_to_base('hello', 'HE')
    assert_equal 'helLO', Rvim::Completion.match_case_to_base('HELLO', 'hel')
    assert_equal 'hello', Rvim::Completion.match_case_to_base('hello', '')
  end
end

class TestIsfnameIsident < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_isfname_default
    assert_match(/48-57/, @editor.settings.get(:isfname))
  end

  def test_isf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set isf=a-z,A-Z,_'))
    assert_equal 'a-z,A-Z,_', @editor.settings.get(:isfname)
  end

  def test_isident_default
    assert_match(/192-255/, @editor.settings.get(:isident))
  end

  def test_isi_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set isi=a-z,A-Z'))
    assert_equal 'a-z,A-Z', @editor.settings.get(:isident)
  end
end

class TestIskeywordStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default
    assert_match(/192-255/, @editor.settings.get(:iskeyword))
  end

  def test_isk_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set isk=a-z,A-Z,_'))
    assert_equal 'a-z,A-Z,_', @editor.settings.get(:iskeyword)
  end
end

class TestMatchpairsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_pairs
    assert_equal '(:),{:},[:]', @editor.settings.get(:matchpairs)
  end

  def test_mps_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mps=(:),{:},[:],<:>'))
    assert_equal '(:),{:},[:],<:>', @editor.settings.get(:matchpairs)
  end
end

class TestFormatoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_tcq
    assert_equal 'tcq', @editor.settings.get(:formatoptions)
  end

  def test_fo_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fo=tcqj'))
    assert_equal 'tcqj', @editor.settings.get(:formatoptions)
  end
end

class TestCommentsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_includes_slashes
    assert_match(%r{//}, @editor.settings.get(:comments))
  end

  def test_com_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set com=:#'))
    assert_equal ':#', @editor.settings.get(:comments)
  end
end

class TestCommentstringStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_block
    # Switched from "/*%s*/" to "# %s" so the built-in gc/gcc
    # operators have a reasonable default before any filetype
    # plugin overrides it.
    assert_equal '# %s', @editor.settings.get(:commentstring)
  end

  def test_cms_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cms=#%s'))
    assert_equal '#%s', @editor.settings.get(:commentstring)
  end
end

class TestWrapmarginStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_zero
    assert_equal 0, @editor.settings.get(:wrapmargin)
  end

  def test_wm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set wm=5'))
    assert_equal 5, @editor.settings.get(:wrapmargin)
  end
end

class TestSelectionStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_inclusive
    assert_equal 'inclusive', @editor.settings.get(:selection)
  end

  def test_sel_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set sel=exclusive'))
    assert_equal 'exclusive', @editor.settings.get(:selection)
  end
end

class TestSelectmodeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:selectmode)
  end

  def test_slm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set slm=mouse,key'))
    assert_equal 'mouse,key', @editor.settings.get(:selectmode)
  end
end

class TestVirtualeditMouseSidescrolloffStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_virtualedit_default_empty
    assert_equal '', @editor.settings.get(:virtualedit)
  end

  def test_set_virtualedit_value
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set virtualedit=onemore'))
    assert_equal 'onemore', @editor.settings.get(:virtualedit)
  end

  def test_ve_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ve=block'))
    assert_equal 'block', @editor.settings.get(:virtualedit)
  end

  def test_mouse_default_empty
    assert_equal '', @editor.settings.get(:mouse)
  end

  def test_set_mouse_value
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mouse=a'))
    assert_equal 'a', @editor.settings.get(:mouse)
  end

  def test_sidescrolloff_default_zero
    assert_equal 0, @editor.settings.get(:sidescrolloff)
  end

  def test_siso_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set siso=5'))
    assert_equal 5, @editor.settings.get(:sidescrolloff)
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

class TestCasemapStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_internal
    assert_match(/internal/, @editor.settings.get(:casemap))
  end

  def test_cmp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set cmp=internal'))
    assert_equal 'internal', @editor.settings.get(:casemap)
  end
end

class TestQuoteescapeStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_backslash
    assert_equal '\\', @editor.settings.get(:quoteescape)
  end

  def test_qe_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set qe=\\\\^'))
    refute_nil @editor.settings.get(:quoteescape)
  end
end

class TestFormatlistpatStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_numbered
    assert_match(/\\d/, @editor.settings.get(:formatlistpat))
  end

  def test_flp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set flp=^*\\\\s'))
    assert_match(/\*/, @editor.settings.get(:formatlistpat))
  end
end

class TestFormatexprStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:formatexpr)
  end

  def test_fex_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set fex=MyFmt()'))
    assert_equal 'MyFmt()', @editor.settings.get(:formatexpr)
  end
end

class TestDigraphStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:digraph)
  end

  def test_dg_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set dg'))
    assert_equal true, @editor.settings.get(:digraph)
  end
end

class TestRevinsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:revins)
  end

  def test_ri_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ri'))
    assert_equal true, @editor.settings.get(:revins)
  end
end

class TestRightleftStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_off
    assert_equal false, @editor.settings.get(:rightleft)
  end

  def test_rl_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set rl'))
    assert_equal true, @editor.settings.get(:rightleft)
  end
end

class TestRightleftcmdStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_search
    assert_equal 'search', @editor.settings.get(:rightleftcmd)
  end

  def test_rlc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set rlc=search'))
    assert_equal 'search', @editor.settings.get(:rightleftcmd)
  end
end

class TestIsprintStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default
    assert_match(/161/, @editor.settings.get(:isprint))
  end

  def test_isp_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set isp=@,161-255'))
    assert_equal '@,161-255', @editor.settings.get(:isprint)
  end
end

class TestStartofline < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.instance_variable_set(:@buffer_of_lines, ['top', '    indented line', '  middle', 'bottom'])
  end

  def fire_g(letter)
    @editor.send(:rvim_g_prefix, nil, arg: nil)
    @editor.instance_variable_get(:@waiting_proc).call(letter, nil)
  end

  def test_default_sol_jumps_to_first_nonblank
    @editor.instance_variable_set(:@line_index, 1)
    @editor.instance_variable_set(:@byte_pointer, 5)
    fire_g('g')
    assert_equal 0, @editor.line_index
    assert_equal 0, @editor.byte_pointer # 'top' starts at col 0
  end

  def test_gg_to_indented_line_lands_on_first_nonblank
    # We need an indented first line for the difference to show
    @editor.instance_variable_set(:@buffer_of_lines, ['  start', 'middle', 'end'])
    @editor.instance_variable_set(:@line_index, 2)
    fire_g('g')
    assert_equal 2, @editor.byte_pointer # past 2 spaces
  end

  def test_sol_off_keeps_cursor_at_zero
    @editor.settings.set(:startofline, false)
    @editor.instance_variable_set(:@buffer_of_lines, ['  start', 'middle'])
    @editor.instance_variable_set(:@line_index, 1)
    fire_g('g')
    assert_equal 0, @editor.byte_pointer
  end

  def test_G_lands_on_first_nonblank
    @editor.instance_variable_set(:@buffer_of_lines, ['top', '  bottom'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.send(:vi_to_history_line, nil, arg: nil)
    assert_equal 1, @editor.line_index
    assert_equal 2, @editor.byte_pointer
  end

  def test_sol_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set nosol'))
    assert_equal false, @editor.settings.get(:startofline)
  end
end
