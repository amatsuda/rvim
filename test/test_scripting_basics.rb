# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestMessages < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_status_message_is_recorded_in_messages
    @editor.status_message = 'hello'
    assert_includes @editor.messages, 'hello'
  end

  def test_messages_command_lists_via_show_list
    @editor.status_message = 'first'
    @editor.status_message = 'second'
    Rvim::Command.execute(@editor, Rvim::Command.parse(':messages'))
    # show_list is consumed; verify we have both queued in @messages
    assert_includes @editor.messages, 'first'
    assert_includes @editor.messages, 'second'
  end

  def test_messages_ring_caps_at_max
    300.times { |i| @editor.status_message = "m#{i}" }
    assert_operator @editor.messages.size, :<=, Rvim::Editor::MESSAGES_MAX
  end
end

class TestSilent < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_silent_clears_inner_status_message
    Rvim::Command.execute(@editor, Rvim::Command.parse(':silent unmap nonexistent'))
    # :unmap on a missing lhs would normally not warn for our impl; force a known
    # error by using :runtime missing.
    @editor.status_message = nil
    Rvim::Command.execute(@editor, Rvim::Command.parse(':silent runtime missing.vim'))
    assert_nil @editor.status_message
  end
end

class TestVerbose < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_verbose_restores_setting_after
    @editor.settings.set(:verbose, 0)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':verbose 5 set ts=4'))
    assert_equal 0, @editor.settings.get(:verbose)
    assert_equal 4, @editor.settings.get(:tabstop)
  end
end

class TestExecute < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_execute_runs_quoted_command
    Rvim::Command.execute(@editor, Rvim::Command.parse(":execute 'set ts=4'"))
    assert_equal 4, @editor.settings.get(:tabstop)
  end

  def test_execute_runs_unquoted_command
    Rvim::Command.execute(@editor, Rvim::Command.parse(':execute set ts=8'))
    assert_equal 8, @editor.settings.get(:tabstop)
  end
end

class TestRedir < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @tmp = Dir.mktmpdir('rvim-redir')
    @path = File.join(@tmp, 'out.log')
  end

  def teardown
    @editor.close_redir
    FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
  end

  def test_redir_to_file_captures_status_messages
    Rvim::Command.execute(@editor, Rvim::Command.parse(":redir > #{@path}"))
    @editor.status_message = 'hello sink'
    @editor.status_message = 'second line'
    Rvim::Command.execute(@editor, Rvim::Command.parse(':redir END'))
    text = File.read(@path)
    assert_match(/hello sink/, text)
    assert_match(/second line/, text)
  end

  def test_redir_invalid_arg_errors
    Rvim::Command.execute(@editor, Rvim::Command.parse(':redir bogus'))
    assert_match(/E474/, @editor.status_message.to_s)
  end
end
