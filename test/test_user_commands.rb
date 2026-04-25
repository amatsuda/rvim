# frozen_string_literal: true

require_relative 'test_helper'

class TestUserCommands < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_define_and_invoke
    Rvim::Command.execute(@editor, Rvim::Command.parse(':command Foo set ts=4'))
    assert @editor.user_commands.key?('Foo')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':Foo'))
    assert_equal 4, @editor.settings.get(:tabstop)
  end

  def test_redefine_without_bang_errors
    Rvim::Command.execute(@editor, Rvim::Command.parse(':command Foo set ts=2'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':command Foo set ts=8'))
    assert_match(/E174/, @editor.status_message.to_s)
  end

  def test_redefine_with_bang_succeeds
    Rvim::Command.execute(@editor, Rvim::Command.parse(':command Foo set ts=2'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':command! Foo set ts=8'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':Foo'))
    assert_equal 8, @editor.settings.get(:tabstop)
  end

  def test_args_substitution
    Rvim::Command.execute(@editor, Rvim::Command.parse(':command -nargs=1 SetTs set ts=<args>'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':SetTs 6'))
    assert_equal 6, @editor.settings.get(:tabstop)
  end

  def test_invalid_name_errors
    Rvim::Command.execute(@editor, Rvim::Command.parse(':command bad set ts=1'))
    assert_match(/E182/, @editor.status_message.to_s)
  end

  def test_delcommand_removes
    Rvim::Command.execute(@editor, Rvim::Command.parse(':command Foo set ts=2'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':delcommand Foo'))
    refute @editor.user_commands.key?('Foo')
  end

  def test_delcommand_unknown_errors
    Rvim::Command.execute(@editor, Rvim::Command.parse(':delcommand Nope'))
    assert_match(/E184/, @editor.status_message.to_s)
  end

  def test_unknown_user_command_returns_E492
    Rvim::Command.execute(@editor, Rvim::Command.parse(':Unknown'))
    assert_match(/E492/, @editor.status_message.to_s)
  end
end
