# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'tmpdir'
require 'fileutils'

class TestBangRepeat < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_bang_remembers_last_command
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!echo hi'))
    assert_equal 'echo hi', @editor.last_bang_cmd
  end

  def test_double_bang_repeats_last
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!echo first'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!!'))
    assert_equal 'echo first', @editor.last_bang_cmd
  end

  def test_double_bang_with_suffix_appends
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!echo'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!! foo'))
    assert_equal 'echo foo', @editor.last_bang_cmd
  end

  def test_double_bang_without_history_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!!'))
    assert_match(/E34/, @editor.status_message.to_s)
  end
end

class TestFilenameExpansion < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_percent_expands_to_filepath
    @editor.instance_variable_set(:@filepath, '/tmp/foo.rb')
    expanded = Rvim::Command.expand_filenames(@editor, 'echo %')
    assert_equal 'echo /tmp/foo.rb', expanded
  end

  def test_hash_expands_to_alternate
    @editor.alternate_filepath = '/tmp/alt.rb'
    expanded = Rvim::Command.expand_filenames(@editor, 'diff #')
    assert_equal 'diff /tmp/alt.rb', expanded
  end

  def test_escape_preserves_literal
    @editor.instance_variable_set(:@filepath, '/x.rb')
    expanded = Rvim::Command.expand_filenames(@editor, 'echo \\% literal')
    assert_equal 'echo % literal', expanded
  end

  def test_no_filepath_leaves_percent_alone
    expanded = Rvim::Command.expand_filenames(@editor, 'echo %')
    assert_equal 'echo %', expanded
  end

  def test_alternate_set_on_swap
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.txt'), "a\n")
      File.write(File.join(dir, 'b.txt'), "b\n")
      @editor.open(File.join(dir, 'a.txt'))
      first = @editor.filepath
      @editor.open(File.join(dir, 'b.txt'))
      assert_equal first, @editor.alternate_filepath
    end
  end
end

class TestArgList < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_set_arg_list
    @editor.set_arg_list(%w[a.txt b.txt])
    assert_equal %w[a.txt b.txt], @editor.arg_list
    assert_equal 0, @editor.arg_index
  end

  def test_args_command_lists
    @editor.set_arg_list(%w[a.txt b.txt])
    Rvim::Command.execute(@editor, Rvim::Command.parse(':args'))
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/a\.txt/, body)
    assert_match(/b\.txt/, body)
  end

  def test_args_no_list_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':args'))
    assert_match(/E163/, @editor.status_message.to_s)
  end

  def test_args_with_files_sets_list
    Rvim::Command.execute(@editor, Rvim::Command.parse(':args foo.txt bar.txt'))
    assert_equal %w[foo.txt bar.txt], @editor.arg_list
  end

  def test_argadd
    @editor.set_arg_list(%w[a])
    Rvim::Command.execute(@editor, Rvim::Command.parse(':argadd b c'))
    assert_equal %w[a b c], @editor.arg_list
  end
end

class TestBufdoTabdoWindo < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_bufdo_runs_command_on_each_buffer
    Dir.mktmpdir do |dir|
      f1 = File.join(dir, 'a.txt')
      f2 = File.join(dir, 'b.txt')
      File.write(f1, "a\n")
      File.write(f2, "b\n")
      @editor.open(f1)
      @editor.open(f2)
      # bufdo set number — should leave number=true after running on each buffer
      Rvim::Command.execute(@editor, Rvim::Command.parse(':bufdo set number'))
      assert_equal true, @editor.settings.get(:number)
    end
  end

  def test_argdo_runs_on_each_arg
    Dir.mktmpdir do |dir|
      f1 = File.join(dir, 'a.txt')
      f2 = File.join(dir, 'b.txt')
      File.write(f1, "first\n")
      File.write(f2, "second\n")
      @editor.set_arg_list([f1, f2])
      Rvim::Command.execute(@editor, Rvim::Command.parse(':argdo set number'))
      assert_equal true, @editor.settings.get(:number)
    end
  end
end

class TestRegistersFilter < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.send(:write_register, 'in a', :char, register: 'a')
    @editor.send(:write_register, 'in b', :char, register: 'b')
    @editor.send(:write_register, 'in c', :char, register: 'c')
  end

  def test_registers_no_filter_lists_all
    Rvim::Command.execute(@editor, Rvim::Command.parse(':registers'))
    body = @editor.list_view.lines.join("\n")
    assert_match(/in a/, body)
    assert_match(/in b/, body)
    assert_match(/in c/, body)
  end

  def test_registers_filter_one
    Rvim::Command.execute(@editor, Rvim::Command.parse(':registers a'))
    body = @editor.list_view.lines.join("\n")
    assert_match(/in a/, body)
    refute_match(/in b/, body)
  end

  def test_registers_filter_multiple
    Rvim::Command.execute(@editor, Rvim::Command.parse(':registers a c'))
    body = @editor.list_view.lines.join("\n")
    assert_match(/in a/, body)
    assert_match(/in c/, body)
    refute_match(/in b/, body)
  end
end
