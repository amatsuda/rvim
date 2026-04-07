# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'tmpdir'
require 'fileutils'

class TestTagsParse < Test::Unit::TestCase
  def setup
    Rvim::Tags.reset!
  end

  def teardown
    Rvim::Tags.reset!
  end

  def test_load_basic_tags_file
    Dir.mktmpdir do |dir|
      tags = File.join(dir, 'tags')
      File.write(tags, <<~TAGS)
        !_TAG_FILE_FORMAT\t2
        foo\tlib/foo.rb\t/^def foo$/
        bar\tlib/bar.rb\t42
      TAGS
      Rvim::Tags.load([tags])
      assert_equal 2, Rvim::Tags.all.size
      assert_equal ['foo', 'bar'], Rvim::Tags.all.map(&:name)
    end
  end

  def test_skips_comment_lines
    Dir.mktmpdir do |dir|
      tags = File.join(dir, 'tags')
      File.write(tags, "!_TAG_PROGRAM_NAME\tctags\nfoo\tx.rb\t1\n")
      Rvim::Tags.load([tags])
      assert_equal 1, Rvim::Tags.all.size
    end
  end

  def test_strips_extensions_after_excmd
    Dir.mktmpdir do |dir|
      tags = File.join(dir, 'tags')
      File.write(tags, %(foo\tx.rb\t/^def foo$/;"\tf\tclass:Bar\n))
      Rvim::Tags.load([tags])
      entry = Rvim::Tags.find('foo').first
      assert_equal '/^def foo$/', entry.excmd
    end
  end

  def test_resolves_relative_path_against_tags_dir
    Dir.mktmpdir do |dir|
      tags = File.join(dir, 'tags')
      File.write(tags, "foo\tlib/foo.rb\t1\n")
      Rvim::Tags.load([tags])
      entry = Rvim::Tags.find('foo').first
      assert_equal File.join(dir, 'lib/foo.rb'), entry.file
    end
  end

  def test_find_returns_multiple_matches
    Dir.mktmpdir do |dir|
      tags = File.join(dir, 'tags')
      File.write(tags, "foo\ta.rb\t1\nfoo\tb.rb\t2\n")
      Rvim::Tags.load([tags])
      assert_equal 2, Rvim::Tags.find('foo').size
    end
  end

  def test_load_skips_missing_files
    Rvim::Tags.load(['/nope/does_not_exist'])
    assert_equal 0, Rvim::Tags.all.size
  end
end

class TestTagsLocate < Test::Unit::TestCase
  def test_line_number
    assert_equal [41, 0], Rvim::Tags.locate('42', %w[a b c])
  end

  def test_pattern_match
    lines = ['# comment', 'def foo', 'def bar']
    assert_equal [1, 0], Rvim::Tags.locate('/^def foo$/', lines)
  end

  def test_pattern_substring
    lines = ['hello there', 'goodbye']
    assert_equal [1, 0], Rvim::Tags.locate('/goodbye/', lines)
  end

  def test_unresolvable_returns_nil
    assert_nil Rvim::Tags.locate('/missing/', %w[a b])
  end
end

class TestTagsEditor < Test::Unit::TestCase
  def setup
    Rvim::Tags.reset!
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def teardown
    Rvim::Tags.reset!
  end

  def test_ctrl_bracket_jumps_to_tag
    Dir.mktmpdir do |dir|
      target = File.join(dir, 'lib', 'foo.rb')
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "module Bar\n  def foo\n  end\nend\n")
      tags = File.join(dir, 'tags')
      File.write(tags, "foo\tlib/foo.rb\t/def foo/\n")

      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.settings.set(:tags, 'tags')
      @editor.instance_variable_set(:@buffer_of_lines, [+'foo()'])
      @editor.instance_variable_set(:@line_index, 0)
      @editor.instance_variable_set(:@byte_pointer, 0)
      @editor.tag_jump('foo')

      assert_equal File.realpath(target), File.realpath(@editor.filepath)
      assert_equal 1, @editor.line_index
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_ctrl_t_pops_back
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "first\n")
      File.write(File.join(dir, 'b.rb'), "def foo\nend\n")
      tags = File.join(dir, 'tags')
      File.write(tags, "foo\tb.rb\t/def foo/\n")
      saved = Dir.pwd
      Dir.chdir(dir)

      @editor.settings.set(:tags, 'tags')
      @editor.open(File.join(dir, 'a.rb'))
      @editor.instance_variable_set(:@line_index, 0)
      @editor.instance_variable_set(:@byte_pointer, 0)
      original = @editor.filepath

      @editor.tag_jump('foo')
      refute_equal original, @editor.filepath

      @editor.tag_pop
      assert_equal original, @editor.filepath
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_unknown_tag_sets_status
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'tags'), "foo\tx.rb\t1\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.settings.set(:tags, 'tags')
      @editor.tag_jump('bogus')
      assert_match(/E426/, @editor.status_message.to_s)
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_tag_pop_empty_stack
    @editor.tag_pop
    assert_match(/E555/, @editor.status_message.to_s)
  end

  def test_tags_listing
    @editor.instance_variable_get(:@tag_stack) << { name: 'foo', file: '/x.rb', line_index: 5, byte_pointer: 0 }
    Rvim::Command.execute(@editor, Rvim::Command.parse(':tags'))
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/foo/, body)
    assert_match(%r{/x\.rb:6}, body)
  end

  def test_tag_command_no_arg_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':tag'))
    assert_match(/E471/, @editor.status_message.to_s)
  end

  def test_tnext_navigates_matches
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "foo\n")
      File.write(File.join(dir, 'b.rb'), "foo\n")
      File.write(File.join(dir, 'tags'), "foo\ta.rb\t1\nfoo\tb.rb\t1\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.settings.set(:tags, 'tags')
      @editor.tag_jump('foo')
      first_file = @editor.filepath
      @editor.tag_next
      assert_not_equal first_file, @editor.filepath
    ensure
      Dir.chdir(saved) if saved
    end
  end
end
