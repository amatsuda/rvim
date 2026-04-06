# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestCmdlineCompletionContext < Test::Unit::TestCase
  def test_empty_buffer_is_command_context
    ctx = Rvim::CmdlineCompletion.analyze('')
    assert_equal :command, ctx.kind
    assert_equal '', ctx.partial
  end

  def test_unfinished_verb_is_command_context
    ctx = Rvim::CmdlineCompletion.analyze('vim')
    assert_equal :command, ctx.kind
    assert_equal 'vim', ctx.partial
  end

  def test_after_e_is_filename_context
    ctx = Rvim::CmdlineCompletion.analyze('e foo')
    assert_equal :filename, ctx.kind
    assert_equal 'foo', ctx.partial
    assert_equal 'e ', ctx.prefix
  end

  def test_after_set_is_setting_context
    ctx = Rvim::CmdlineCompletion.analyze('set num')
    assert_equal :setting, ctx.kind
    assert_equal 'num', ctx.partial
  end

  def test_set_no_prefix_strip
    ctx = Rvim::CmdlineCompletion.analyze('set noi')
    assert_equal :setting, ctx.kind
    # Expanded against 'i' so 'ignorecase' matches; the 'no' is preserved in prefix
    assert_equal 'i', ctx.partial
    assert_equal 'set no', ctx.prefix
  end

  def test_unknown_verb_no_completion
    ctx = Rvim::CmdlineCompletion.analyze('xyzzy hello')
    assert_equal :none, ctx.kind
  end
end

class TestCmdlineCompletionCandidates < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_command_candidates_filtered_by_prefix
    ctx = Rvim::CmdlineCompletion::Context.new(kind: :command, partial: 'tab', prefix: '')
    candidates = Rvim::CmdlineCompletion.candidates(ctx, @editor)
    assert candidates.include?('tabnew')
    assert candidates.include?('tabnext')
    refute candidates.include?('quit')
  end

  def test_setting_candidates
    ctx = Rvim::CmdlineCompletion::Context.new(kind: :setting, partial: 'num', prefix: 'set ')
    candidates = Rvim::CmdlineCompletion.candidates(ctx, @editor)
    assert_equal ['number'], candidates
  end

  def test_filename_candidates
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'alpha.txt'), 'a')
      File.write(File.join(dir, 'alphabet.txt'), 'b')
      File.write(File.join(dir, 'beta.txt'), 'c')
      saved = Dir.pwd
      Dir.chdir(dir)
      ctx = Rvim::CmdlineCompletion::Context.new(kind: :filename, partial: 'alpha', prefix: 'e ')
      candidates = Rvim::CmdlineCompletion.candidates(ctx, @editor)
      assert candidates.include?('alpha.txt')
      assert candidates.include?('alphabet.txt')
      refute candidates.include?('beta.txt')
    ensure
      Dir.chdir(saved) if saved
    end
  end
end

class TestCmdlineTabDispatch < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def k(ch)
    Reline::Key.new(ch, nil, false)
  end

  def test_tab_in_ex_prompt_completes_command
    @editor.send(:rvim_enter_command_mode, nil)
    'tabn'.each_char { |c| @editor.update(k(c)) }
    @editor.update(k("\t"))
    refute_nil @editor.cmdline_popup
    assert @editor.prompt_buffer.start_with?('tabn')
    # First match alphabetical is 'tabnew' (followed by 'tabnext')
    assert_equal 'tabnew', @editor.prompt_buffer
  end

  def test_tab_cycles_through_candidates
    @editor.send(:rvim_enter_command_mode, nil)
    'tabn'.each_char { |c| @editor.update(k(c)) }
    @editor.update(k("\t"))
    first = @editor.prompt_buffer.dup
    @editor.update(k("\t"))
    second = @editor.prompt_buffer
    refute_equal first, second
  end

  def test_tab_completes_setting_after_set
    @editor.send(:rvim_enter_command_mode, nil)
    'set numb'.each_char { |c| @editor.update(k(c)) }
    @editor.update(k("\t"))
    assert_equal 'set number', @editor.prompt_buffer
  end

  def test_typing_other_char_clears_popup
    @editor.send(:rvim_enter_command_mode, nil)
    'tabn'.each_char { |c| @editor.update(k(c)) }
    @editor.update(k("\t"))
    refute_nil @editor.cmdline_popup
    @editor.update(k('x'))
    assert_nil @editor.cmdline_popup
  end

  def test_enter_executes_with_completed_value
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'demo.txt'), "hello\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.send(:rvim_enter_command_mode, nil)
      'e dem'.each_char { |c| @editor.update(k(c)) }
      @editor.update(k("\t"))
      assert_equal 'e demo.txt', @editor.prompt_buffer
      @editor.update(k("\r"))
      assert_equal 'demo.txt', File.basename(@editor.filepath.to_s)
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_no_match_does_nothing
    @editor.send(:rvim_enter_command_mode, nil)
    'XYZNEVER'.each_char { |c| @editor.update(k(c)) }
    @editor.update(k("\t"))
    assert_nil @editor.cmdline_popup
    assert_equal 'XYZNEVER', @editor.prompt_buffer
  end
end
