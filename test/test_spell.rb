# frozen_string_literal: true

require_relative 'test_helper'
require 'set'
require 'tmpdir'
require 'fileutils'

class TestSpellAlgorithm < Test::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir
    @prev_xdg = ENV['XDG_CACHE_HOME']
    ENV['XDG_CACHE_HOME'] = @dir
    Rvim::Spell.reset!
    Rvim::Spell.dict = Set.new(%w[hello world ruby ruvi rvim there their they])
    Rvim::Spell.good_set = Set.new
    Rvim::Spell.bad_set = Set.new
  end

  def teardown
    ENV['XDG_CACHE_HOME'] = @prev_xdg
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
    Rvim::Spell.reset!
  end

  def test_misspelled_returns_true_for_unknown_word
    assert_equal true, Rvim::Spell.misspelled?('thiss')
  end

  def test_misspelled_returns_false_for_known_word
    assert_equal false, Rvim::Spell.misspelled?('hello')
  end

  def test_misspelled_is_case_insensitive
    assert_equal false, Rvim::Spell.misspelled?('Hello')
    assert_equal false, Rvim::Spell.misspelled?('HELLO')
  end

  def test_misspelled_skips_numeric_or_empty
    assert_equal false, Rvim::Spell.misspelled?('')
    assert_equal false, Rvim::Spell.misspelled?(nil)
    assert_equal false, Rvim::Spell.misspelled?('42')
  end

  def test_good_set_overrides_dict_miss
    Rvim::Spell.add_good('zorp')
    assert_equal false, Rvim::Spell.misspelled?('zorp')
  end

  def test_bad_set_overrides_dict_hit
    Rvim::Spell.add_bad('hello')
    assert_equal true, Rvim::Spell.misspelled?('hello')
  end

  def test_distance_basic
    assert_equal 0, Rvim::Spell.distance('cat', 'cat')
    assert_equal 1, Rvim::Spell.distance('cat', 'cot')
    assert_equal 1, Rvim::Spell.distance('cat', 'cats')
    assert_equal 3, Rvim::Spell.distance('cat', 'dog')
  end

  def test_suggest_returns_close_matches
    suggestions = Rvim::Spell.suggest('helo', max_dist: 2)
    assert suggestions.include?('hello')
  end

  def test_suggest_filters_by_max_dist
    suggestions = Rvim::Spell.suggest('xxxxxx', max_dist: 1)
    assert_equal [], suggestions
  end
end

class TestSpellPersistence < Test::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir
    @prev_xdg = ENV['XDG_CACHE_HOME']
    ENV['XDG_CACHE_HOME'] = @dir
    Rvim::Spell.reset!
    Rvim::Spell.dict = Set.new(%w[hello])
    Rvim::Spell.good_set = Set.new
    Rvim::Spell.bad_set = Set.new
  end

  def teardown
    ENV['XDG_CACHE_HOME'] = @prev_xdg
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
    Rvim::Spell.reset!
  end

  def test_add_good_persists_to_disk
    Rvim::Spell.add_good('zorp')
    path = File.join(Rvim::Spell.cache_dir, 'good.txt')
    assert File.exist?(path)
    assert_match(/zorp/, File.read(path))
  end

  def test_add_bad_persists_to_disk
    Rvim::Spell.add_bad('hello')
    path = File.join(Rvim::Spell.cache_dir, 'bad.txt')
    assert File.exist?(path)
    assert_match(/hello/, File.read(path))
  end
end

class TestSpellEditorIntegration < Test::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir
    @prev_xdg = ENV['XDG_CACHE_HOME']
    ENV['XDG_CACHE_HOME'] = @dir
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
    Rvim::Spell.reset!
    Rvim::Spell.dict = Set.new(%w[hello world this is fine])
    Rvim::Spell.good_set = Set.new
    Rvim::Spell.bad_set = Set.new
  end

  def teardown
    ENV['XDG_CACHE_HOME'] = @prev_xdg
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
    Rvim::Spell.reset!
  end

  def buf(*lines, line: 0, byte: 0)
    @editor.instance_variable_set(:@buffer_of_lines, lines.map { |l| +l })
    @editor.instance_variable_set(:@line_index, line)
    @editor.instance_variable_set(:@byte_pointer, byte)
  end

  def test_jump_to_misspelling_next
    @editor.settings.set(:spell, true)
    buf('hello world wrng more')
    @editor.jump_to_misspelling(:next)
    assert_equal 12, @editor.byte_pointer # start of 'wrng'
  end

  def test_jump_to_misspelling_skips_when_spell_off
    @editor.settings.set(:spell, false)
    buf('hello wrng')
    @editor.jump_to_misspelling(:next)
    assert_equal 0, @editor.byte_pointer
  end

  def test_jump_to_misspelling_across_lines
    @editor.settings.set(:spell, true)
    Rvim::Spell.dict = Set.new(%w[hello world all is fine])
    buf('hello world', 'all is fine', 'somthing wrng')
    @editor.jump_to_misspelling(:next)
    assert_equal 2, @editor.line_index
    assert_equal 0, @editor.byte_pointer # 'somthing'
  end

  def test_zg_adds_word_to_good_list
    buf('thisisamadeupword extra', byte: 0)
    @editor.spell_add_word_at_cursor(:good)
    assert Rvim::Spell.good_set.include?('thisisamadeupword')
  end

  def test_z_equals_shows_suggestions
    @editor.settings.set(:spell, true)
    buf('helo', byte: 0)
    @editor.spell_show_suggestions
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/hello/, body)
  end

  def test_z_equals_no_op_for_correct_word
    @editor.settings.set(:spell, true)
    buf('hello', byte: 0)
    @editor.spell_show_suggestions
    assert_nil @editor.list_view
  end
end

class TestSpellRender < Test::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir
    @prev_xdg = ENV['XDG_CACHE_HOME']
    ENV['XDG_CACHE_HOME'] = @dir
    @editor = Rvim::Editor.new(Reline.core.config)
    @screen = Rvim::Screen.new(@editor)
    Rvim::Spell.reset!
    Rvim::Spell.dict = Set.new(%w[hello world])
    Rvim::Spell.good_set = Set.new
    Rvim::Spell.bad_set = Set.new
  end

  def teardown
    ENV['XDG_CACHE_HOME'] = @prev_xdg
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
    Rvim::Spell.reset!
  end

  def test_render_wraps_misspelled_word_when_spell_on
    @editor.settings.set(:spell, true)
    out = @screen.send(:render_line, 'hello wrldz')
    assert_match(/\e\[31mwrldz\e\[39m/, out)
    refute_match(/\e\[31mhello\e\[39m/, out)
  end

  def test_render_skips_spell_when_setting_off
    @editor.settings.set(:spell, false)
    out = @screen.send(:render_line, 'hello wrldz')
    refute_match(/\e\[31m/, out)
  end
end
