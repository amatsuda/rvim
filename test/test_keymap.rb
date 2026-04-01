# frozen_string_literal: true

require_relative 'test_helper'

class TestKeymapExpand < Test::Unit::TestCase
  def test_expand_cr
    assert_equal "\r", Rvim::Keymap.expand('<CR>')
    assert_equal "\r", Rvim::Keymap.expand('<cr>')
    assert_equal "\r", Rvim::Keymap.expand('<Enter>')
  end

  def test_expand_esc
    assert_equal "\e", Rvim::Keymap.expand('<Esc>')
  end

  def test_expand_tab
    assert_equal "\t", Rvim::Keymap.expand('<Tab>')
  end

  def test_expand_space
    assert_equal ' ', Rvim::Keymap.expand('<Space>')
  end

  def test_expand_bs
    assert_equal "\x7f", Rvim::Keymap.expand('<BS>')
  end

  def test_expand_ctrl
    assert_equal "\x01", Rvim::Keymap.expand('<C-a>')
    assert_equal "\x01", Rvim::Keymap.expand('<C-A>')
    assert_equal "\x18", Rvim::Keymap.expand('<C-x>')
  end

  def test_expand_shift
    assert_equal 'X', Rvim::Keymap.expand('<S-x>')
  end

  def test_expand_leader
    assert_equal '\\', Rvim::Keymap.expand('<leader>')
  end

  def test_expand_leader_takes_kwarg
    assert_equal ',', Rvim::Keymap.expand('<leader>', leader: ',')
    assert_equal ',w', Rvim::Keymap.expand('<leader>w', leader: ',')
  end

  def test_expand_arrow_keys
    assert_equal "\e[A", Rvim::Keymap.expand('<Up>')
    assert_equal "\e[B", Rvim::Keymap.expand('<Down>')
    assert_equal "\e[C", Rvim::Keymap.expand('<Right>')
    assert_equal "\e[D", Rvim::Keymap.expand('<Left>')
  end

  def test_expand_navigation_keys
    assert_equal "\e[H", Rvim::Keymap.expand('<Home>')
    assert_equal "\e[F", Rvim::Keymap.expand('<End>')
    assert_equal "\e[5~", Rvim::Keymap.expand('<PageUp>')
    assert_equal "\e[6~", Rvim::Keymap.expand('<PageDown>')
    assert_equal "\e[2~", Rvim::Keymap.expand('<Insert>')
    assert_equal "\e[3~", Rvim::Keymap.expand('<Delete>')
  end

  def test_expand_nl_nul
    assert_equal "\n", Rvim::Keymap.expand('<NL>')
    assert_equal "\n", Rvim::Keymap.expand('<LF>')
    assert_equal "\x00", Rvim::Keymap.expand('<Nul>')
  end
end

class TestKeymapRender < Test::Unit::TestCase
  def test_render_passes_through_printable
    assert_equal 'y$', Rvim::Keymap.render('y$')
  end

  def test_render_special_keys
    assert_equal '<Esc>', Rvim::Keymap.render("\e")
    assert_equal '<CR>', Rvim::Keymap.render("\r")
    assert_equal ':w<CR>', Rvim::Keymap.render(":w\r")
  end

  def test_render_arrow_keys_long_first
    # \e on its own would be <Esc>, but \e[A should fully match <Up>.
    assert_equal '<Up>', Rvim::Keymap.render("\e[A")
    assert_equal '<Down>', Rvim::Keymap.render("\e[B")
  end

  def test_render_control_chars
    assert_equal '<C-A>', Rvim::Keymap.render("\x01")
    assert_equal '<C-X>', Rvim::Keymap.render("\x18")
  end

  def test_expand_combined
    assert_equal "\\w", Rvim::Keymap.expand('<leader>w')
    assert_equal ":w\r", Rvim::Keymap.expand(':w<CR>')
    assert_equal "y$", Rvim::Keymap.expand('y$')
  end

  def test_expand_unknown_tag_preserved
    assert_equal '<F99>', Rvim::Keymap.expand('<F99>')
  end

  def test_expand_unmatched_lt
    assert_equal '<no close', Rvim::Keymap.expand('<no close')
  end

  def test_expand_lt_gt_escapes
    assert_equal '<>', Rvim::Keymap.expand('<lt><gt>')
  end
end

class TestKeymapTable < Test::Unit::TestCase
  def setup
    @km = Rvim::Keymap.new
  end

  def test_add_and_lookup_exact
    @km.add(:normal, 'Y', 'y$')
    result, mapping = @km.lookup(:normal, 'Y')
    assert_equal :exact, result
    assert_equal 'y$', mapping.rhs
    assert_equal true, mapping.recursive
  end

  def test_add_noremap_flag
    @km.add(:insert, 'jk', "\e", recursive: false)
    _, mapping = @km.lookup(:insert, 'jk')
    assert_equal false, mapping.recursive
  end

  def test_lookup_prefix
    @km.add(:normal, 'gw', 'something')
    result, mapping = @km.lookup(:normal, 'g')
    assert_equal :prefix, result
    assert_nil mapping
  end

  def test_lookup_none
    @km.add(:normal, 'Y', 'y$')
    result, _ = @km.lookup(:normal, 'X')
    assert_equal :none, result
  end

  def test_lookup_exact_wins_over_prefix
    @km.add(:normal, 'g', 'foo')
    @km.add(:normal, 'gw', 'bar')
    result, mapping = @km.lookup(:normal, 'g')
    # g is both an exact match AND a prefix to gw — exact takes precedence,
    # but a 'prefix' return is reasonable since gw could still match.
    # Our impl returns :exact for the unambiguous direct hit, then leaves
    # disambiguation to the state machine. (We test :prefix below for the
    # case where ONLY a prefix match exists.)
    assert_equal :exact, result
    assert_equal 'foo', mapping.rhs
  end

  def test_remove
    @km.add(:normal, 'Y', 'y$')
    @km.remove(:normal, 'Y')
    result, _ = @km.lookup(:normal, 'Y')
    assert_equal :none, result
  end

  def test_clear
    @km.add(:normal, 'Y', 'y$')
    @km.add(:normal, 'X', 'x')
    @km.clear(:normal)
    assert_equal true, @km.empty?(:normal)
  end

  def test_per_mode_isolation
    @km.add(:normal, 'jk', 'foo')
    result, _ = @km.lookup(:insert, 'jk')
    assert_equal :none, result
  end

  def test_add_multi_mode
    @km.add(%i[normal visual op_pending], 'Y', 'y$')
    %i[normal visual op_pending].each do |mode|
      result, _ = @km.lookup(mode, 'Y')
      assert_equal :exact, result, "expected :exact for #{mode}"
    end
  end
end

class TestKeymapModeRouting < Test::Unit::TestCase
  def test_modes_for_map
    assert_equal %i[normal visual op_pending], Rvim::Keymap.modes_for(:map)
    assert_equal %i[normal visual op_pending], Rvim::Keymap.modes_for(:noremap)
  end

  def test_modes_for_specific
    assert_equal %i[normal], Rvim::Keymap.modes_for(:nmap)
    assert_equal %i[insert], Rvim::Keymap.modes_for(:imap)
    assert_equal %i[visual], Rvim::Keymap.modes_for(:vmap)
    assert_equal %i[op_pending], Rvim::Keymap.modes_for(:omap)
  end

  def test_noremap_predicate
    assert Rvim::Keymap.noremap?(:noremap)
    assert Rvim::Keymap.noremap?(:nnoremap)
    assert Rvim::Keymap.noremap?(:inoremap)
    refute Rvim::Keymap.noremap?(:nmap)
    refute Rvim::Keymap.noremap?(:imap)
  end

  def test_unmap_predicate
    assert Rvim::Keymap.unmap?(:unmap)
    assert Rvim::Keymap.unmap?(:nunmap)
    refute Rvim::Keymap.unmap?(:nmap)
  end

  def test_mapclear_predicate
    assert Rvim::Keymap.mapclear?(:mapclear)
    assert Rvim::Keymap.mapclear?(:nmapclear)
    refute Rvim::Keymap.mapclear?(:unmap)
  end
end
