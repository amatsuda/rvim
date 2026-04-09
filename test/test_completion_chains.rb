# frozen_string_literal: true

require_relative 'test_helper'
require 'set'
require 'tmpdir'
require 'fileutils'

class TestCompletionSourceFunctions < Test::Unit::TestCase
  def test_path_base_at_walks_non_whitespace
    line = 'edit lib/foo'
    assert_equal 'lib/foo', Rvim::Completion.path_base_at(line, line.length)
    assert_equal 'lib/', Rvim::Completion.path_base_at(line, 9)
  end

  def test_path_base_at_empty_when_after_whitespace
    line = 'edit '
    assert_equal '', Rvim::Completion.path_base_at(line, line.length)
  end

  def test_candidates_files
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'alpha.txt'), '')
      File.write(File.join(dir, 'beta.txt'), '')
      saved = Dir.pwd
      Dir.chdir(dir)
      assert_equal ['alpha.txt'], Rvim::Completion.candidates_files('alp')
      assert_equal ['alpha.txt', 'beta.txt'], Rvim::Completion.candidates_files('')
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_candidates_files_appends_slash_for_dirs
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, 'subdir'))
      saved = Dir.pwd
      Dir.chdir(dir)
      assert_equal ['subdir/'], Rvim::Completion.candidates_files('sub')
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_candidates_dictionary
    Rvim::Spell.reset!
    Rvim::Spell.dict = Set.new(%w[hello help hero hi water])
    Rvim::Spell.good_set = Set.new
    Rvim::Spell.bad_set = Set.new
    assert_equal %w[hello help hero], Rvim::Completion.candidates_dictionary('he')
  ensure
    Rvim::Spell.reset!
  end

  def test_candidates_lines
    buffer = ['def foo', '  body', 'def bar', '  body', '']
    assert_equal ['def bar', 'def foo'], Rvim::Completion.candidates_lines(buffer, 'def')
  end

  def test_candidates_lines_empty_base_returns_unique_lines
    buffer = ['a', 'b', 'a', '']
    assert_equal %w[a b], Rvim::Completion.candidates_lines(buffer, '')
  end
end

class TestCtrlXDispatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_insert
  end

  def teardown
    Rvim::Spell.reset!
  end

  def k(ch, sym = nil)
    sym ||= @editor.send(:synthesize_key, ch).method_symbol
    Reline::Key.new(ch, sym, false)
  end

  def fire_ctrl_x
    @editor.send(:rvim_completion_chain, nil)
  end

  def test_ctrl_x_ctrl_f_filename_completion
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'alpha.txt'), '')
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.instance_variable_set(:@buffer_of_lines, [+'alp'])
      @editor.instance_variable_set(:@line_index, 0)
      @editor.instance_variable_set(:@byte_pointer, 3)
      fire_ctrl_x
      @editor.update(k("\x06"))
      assert_equal 'alpha.txt', @editor.buffer_of_lines[0]
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_ctrl_x_ctrl_l_line_completion
    @editor.instance_variable_set(:@buffer_of_lines, [+'def foo', +'  body', +'def bar', +'def'])
    @editor.instance_variable_set(:@line_index, 3)
    @editor.instance_variable_set(:@byte_pointer, 3)
    fire_ctrl_x
    @editor.update(k("\x0C"))
    # Replaces the whole line ('def') with first matching line
    assert_equal 'def bar', @editor.buffer_of_lines[3]
    assert_equal true, @editor.completion_active
  end

  def test_ctrl_x_ctrl_k_dictionary_completion
    Rvim::Spell.reset!
    Rvim::Spell.dict = Set.new(%w[hello help hero])
    Rvim::Spell.good_set = Set.new
    Rvim::Spell.bad_set = Set.new
    @editor.instance_variable_set(:@buffer_of_lines, [+'he'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 2)
    fire_ctrl_x
    @editor.update(k("\x0B"))
    assert_equal 'hello', @editor.buffer_of_lines[0]
  end

  def test_unknown_chain_key_sets_status
    @editor.instance_variable_set(:@buffer_of_lines, [+''])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
    fire_ctrl_x
    @editor.update(k('z'))
    assert_match(/unknown completion source/, @editor.status_message.to_s)
  end

  def test_no_match_sets_pattern_not_found
    @editor.instance_variable_set(:@buffer_of_lines, [+'xyz'])
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 3)
    fire_ctrl_x
    @editor.update(k("\x0C"))
    # 'xyz' has no other matching line
    assert_match(/Pattern not found/, @editor.status_message.to_s)
  end
end
