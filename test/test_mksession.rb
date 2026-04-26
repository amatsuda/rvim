# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestMksession < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @tmp = Dir.mktmpdir('rvim-mks')
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
  end

  def test_writes_default_session_filename
    target = File.join(@tmp, 'Session.vim')
    Dir.chdir(@tmp) do
      Rvim::Command.execute(@editor, Rvim::Command.parse(':mksession'))
    end
    assert File.exist?(target)
    contents = File.read(target)
    assert_match(/^cd /, contents)
  end

  def test_writes_named_session
    target = File.join(@tmp, 'my.vim')
    Rvim::Command.execute(@editor, Rvim::Command.parse(":mksession #{target}"))
    assert File.exist?(target)
  end

  def test_existing_session_without_bang_errors
    target = File.join(@tmp, 'exists.vim')
    File.write(target, 'old')
    Rvim::Command.execute(@editor, Rvim::Command.parse(":mksession #{target}"))
    assert_match(/E189/, @editor.status_message.to_s)
  end

  def test_existing_session_with_bang_overwrites
    target = File.join(@tmp, 'exists.vim')
    File.write(target, 'old')
    Rvim::Command.execute(@editor, Rvim::Command.parse(":mksession! #{target}"))
    refute_match(/E189/, @editor.status_message.to_s)
    refute_equal 'old', File.read(target).strip
  end

  def test_includes_open_buffers
    file_a = File.join(@tmp, 'a.txt')
    file_b = File.join(@tmp, 'b.txt')
    File.write(file_a, "hello\n")
    File.write(file_b, "world\n")
    @editor.open(file_a)
    @editor.open(file_b)
    target = File.join(@tmp, 'Session.vim')
    Rvim::Command.execute(@editor, Rvim::Command.parse(":mksession #{target}"))
    contents = File.read(target)
    assert_match(/badd .+a\.txt/, contents)
    assert_match(/badd .+b\.txt/, contents)
    assert_match(/edit .+b\.txt/, contents)
  end

  def test_session_can_be_sourced
    file_a = File.join(@tmp, 'a.txt')
    File.write(file_a, "hi\n")
    @editor.open(file_a)
    target = File.join(@tmp, 'Session.vim')
    Rvim::Command.execute(@editor, Rvim::Command.parse(":mksession #{target}"))

    fresh = Rvim::Editor.new(Reline.core.config)
    fresh.source(target)
    assert_equal file_a, fresh.filepath
  end
end
