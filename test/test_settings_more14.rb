# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'tmpdir'

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

class TestEndofline < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_on
    assert_equal true, @editor.settings.get(:endofline)
  end

  def test_eol_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set noeol'))
    assert_equal false, @editor.settings.get(:endofline)
  end

  def test_save_writes_trailing_newline_when_on
    f = Tempfile.new(['eol', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.save
    bytes = File.binread(f.path)
    assert_equal "changed\n", bytes
  ensure
    f&.unlink
  end

  def test_save_no_trailing_newline_when_both_off
    f = Tempfile.new(['eol', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.settings.set(:endofline, false)
    @editor.settings.set(:fixendofline, false)
    @editor.save
    bytes = File.binread(f.path)
    assert_equal 'changed', bytes
  ensure
    f&.unlink
  end

  def test_fixendofline_forces_trailing_newline
    f = Tempfile.new(['eol', '.txt'])
    f.binmode; f.write("hello\n"); f.close
    @editor.open(f.path)
    @editor.buffer_of_lines[0] = +'changed'
    @editor.settings.set(:endofline, false)
    @editor.settings.set(:fixendofline, true)
    @editor.save
    bytes = File.binread(f.path)
    assert_equal "changed\n", bytes
  ensure
    f&.unlink
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
