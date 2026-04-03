# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestAutocommandsPattern < Test::Unit::TestCase
  def re(pat)
    Rvim::Autocommands.pattern_to_regex(pat)
  end

  def test_star_matches_anything
    assert re('*').match?('foo')
    assert re('*').match?('a/b/c.rb')
  end

  def test_extension_glob
    assert re('*.rb').match?('foo.rb')
    assert re('*.rb').match?('a/b/foo.rb')
    refute re('*.rb').match?('foo.txt')
  end

  def test_question_mark
    assert re('a?c').match?('abc')
    refute re('a?c').match?('abbc')
  end

  def test_brace_alternation
    assert re('*.{rb,erb}').match?('a.rb')
    assert re('*.{rb,erb}').match?('a.erb')
    refute re('*.{rb,erb}').match?('a.txt')
  end

  def test_exact_match
    assert re('Rakefile').match?('Rakefile')
    refute re('Rakefile').match?('foo/Rakefile')
  end
end

class TestAutocommandsTable < Test::Unit::TestCase
  def setup
    @ac = Rvim::Autocommands.new
  end

  def test_add_and_size
    @ac.add('BufRead', '*.rb', 'set sw=2')
    assert_equal 1, @ac.size
  end

  def test_add_multiple_events
    @ac.add(%w[BufRead BufNewFile], '*.rb', 'set sw=2')
    assert_equal 2, @ac.size
  end

  def test_add_multiple_patterns
    @ac.add('BufRead', %w[*.rb *.erb], 'set sw=2')
    assert_equal 2, @ac.size
  end

  def test_event_normalized_to_lowercase_symbol
    @ac.add('BufRead', '*.rb', 'set sw=2')
    captured = nil
    @ac.each { |x| captured = x }
    assert_equal :bufread, captured.event
  end

  def test_remove_by_event_and_pattern
    @ac.add('BufRead', '*.rb', 'set sw=2')
    @ac.add('BufWrite', '*.rb', 'set sw=4')
    @ac.remove(event: 'BufRead', pattern: '*.rb', group: nil)
    assert_equal 1, @ac.size
  end

  def test_clear_group
    @ac.current_group = 'mygroup'
    @ac.add('BufRead', '*', 'set sw=2')
    @ac.current_group = nil
    @ac.add('BufRead', '*', 'set sw=4')
    @ac.clear_group('mygroup')
    assert_equal 1, @ac.size
  end
end

class TestAutocommandsFiring < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_bufread_fires_for_matching_pattern
    file = Tempfile.new(['ac', '.rb'])
    file.write("class Foo\nend\n")
    file.close

    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd BufRead *.rb set number'))
    @editor.open(file.path)
    assert_equal true, @editor.settings.get(:number)
  ensure
    file&.unlink
  end

  def test_bufread_skips_nonmatching_pattern
    file = Tempfile.new(['ac', '.txt'])
    file.write("hello\n")
    file.close

    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd BufRead *.rb set number'))
    @editor.open(file.path)
    assert_equal false, @editor.settings.get(:number)
  ensure
    file&.unlink
  end

  def test_filetype_event_fires
    file = Tempfile.new(['ac', '.rb'])
    file.write("class Foo\nend\n")
    file.close

    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd FileType ruby set number'))
    @editor.open(file.path)
    assert_equal true, @editor.settings.get(:number)
  ensure
    file&.unlink
  end

  def test_bufwritepre_and_post_fire
    file = Tempfile.new(['ac', '.txt'])
    file.write("seed\n")
    file.close

    @editor.open(file.path)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd BufWritePre * let pre = "fired"'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd BufWritePost * let post = "fired"'))
    @editor.save
    assert_equal 'fired', @editor.let_vars['pre']
    assert_equal 'fired', @editor.let_vars['post']
  ensure
    file&.unlink
  end

  def test_insertenter_and_leave_fire
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd InsertEnter * let i_in = "1"'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd InsertLeave * let i_out = "1"'))
    pre_mode = :vi_command
    @editor.config.editing_mode = :vi_insert
    @editor.send(:capture_special_marks, [], pre_mode)
    assert_equal '1', @editor.let_vars['i_in']

    pre_mode = :vi_insert
    @editor.config.editing_mode = :vi_command
    @editor.send(:capture_special_marks, [], pre_mode)
    assert_equal '1', @editor.let_vars['i_out']
  end

  def test_multi_event_registration_fires_each
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd BufRead,BufEnter * let n = "x"'))
    file = Tempfile.new(['ac', '.txt'])
    file.write("a\n")
    file.close
    @editor.open(file.path)
    assert_equal 'x', @editor.let_vars['n']
  ensure
    file&.unlink
  end

  def test_augroup_groups_entries
    Rvim::Command.execute(@editor, Rvim::Command.parse(':augroup mygroup'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd BufRead *.rb set sw=4'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':augroup END'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd BufRead *.rb set sw=8'))
    assert_equal 2, @editor.autocommands.size

    # Re-enter group, then :autocmd! clears just the group's entries
    Rvim::Command.execute(@editor, Rvim::Command.parse(':augroup mygroup'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd!'))
    assert_equal 1, @editor.autocommands.size
  end

  def test_autocmd_listing_no_args
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd BufRead *.rb set sw=2'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':autocmd'))
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/bufread/, body)
    assert_match(/\*.rb/, body)
  end

  def test_recursion_guard
    # Firing should never raise even with a no-op command; just smoke-test.
    @editor.autocommands.add('BufRead', '*', 'set number')
    assert_nothing_raised do
      @editor.autocommands.fire(:bufread, 'foo', @editor)
    end
  end
end
