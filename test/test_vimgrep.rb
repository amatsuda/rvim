# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'tempfile'
require 'fileutils'

class TestQuickfixStorage < Test::Unit::TestCase
  def setup
    @qf = Rvim::Quickfix.new
  end

  def entry(file, line, col, text)
    Rvim::Quickfix::Entry.new(file: file, line: line, col: col, text: text)
  end

  def test_set_and_size
    @qf.set([entry('a.rb', 1, 1, 'foo')])
    assert_equal 1, @qf.size
    assert_equal false, @qf.empty?
  end

  def test_advance_clamps_at_ends
    @qf.set([entry('a.rb', 1, 1, 'a'), entry('a.rb', 2, 1, 'b')])
    assert_equal 0, @qf.index
    @qf.advance(+1)
    assert_equal 1, @qf.index
    @qf.advance(+1) # at last, stays
    assert_equal 1, @qf.index
    @qf.advance(-1)
    assert_equal 0, @qf.index
    @qf.advance(-1)
    assert_equal 0, @qf.index
  end

  def test_at_returns_entry_and_updates_index
    @qf.set([entry('a', 1, 1, 'x'), entry('b', 2, 1, 'y'), entry('c', 3, 1, 'z')])
    e = @qf.at(2)
    assert_equal 'c', e.file
    assert_equal 2, @qf.index
  end

  def test_clear
    @qf.set([entry('a', 1, 1, 'x')])
    @qf.clear
    assert_equal true, @qf.empty?
    assert_equal 0, @qf.index
  end
end

class TestVimgrepExecute < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, 'a.rb'), "foo\nTODO: do this\nbar\n")
    File.write(File.join(@dir, 'b.rb'), "nothing\nTODO: again\n")
    File.write(File.join(@dir, 'c.txt'), "TODO: in txt\n")
    @saved = Dir.pwd
    Dir.chdir(@dir)
  end

  def teardown
    Dir.chdir(@saved)
    FileUtils.remove_entry(@dir) if @dir
  end

  def test_vimgrep_populates_quickfix
    Rvim::Command.execute(@editor, Rvim::Command.parse(':vimgrep! /TODO/ *.rb'))
    assert_equal 2, @editor.quickfix.size
    files = @editor.quickfix.entries.map(&:file).sort
    assert_equal ['a.rb', 'b.rb'], files
  end

  def test_vimgrep_pattern_with_special_chars
    File.write(File.join(@dir, 'd.rb'), "name: 'foo'\n")
    Rvim::Command.execute(@editor, Rvim::Command.parse(":vimgrep! /name:\\s*'\\w+'/ d.rb"))
    assert_equal 1, @editor.quickfix.size
  end

  def test_vimgrep_no_match
    Rvim::Command.execute(@editor, Rvim::Command.parse(':vimgrep! /XYZNOMATCH/ *.rb'))
    assert_equal true, @editor.quickfix.empty?
    assert_match(/E480/, @editor.status_message.to_s)
  end

  def test_vimgrep_jumps_to_first_match
    Rvim::Command.execute(@editor, Rvim::Command.parse(':vimgrep /TODO/ *.rb'))
    # Without bang, we jump. First entry is in a.rb line 2.
    assert_equal 'a.rb', @editor.filepath
    assert_equal 1, @editor.line_index # 0-based
  end

  def test_vimgrep_bang_does_not_jump
    Rvim::Command.execute(@editor, Rvim::Command.parse(':vimgrep! /TODO/ *.rb'))
    # No file opened
    assert_nil @editor.filepath
  end

  def test_cnext_advances_through_matches
    Rvim::Command.execute(@editor, Rvim::Command.parse(':vimgrep /TODO/ *.rb'))
    assert_equal 0, @editor.quickfix.index
    Rvim::Command.execute(@editor, Rvim::Command.parse(':cnext'))
    assert_equal 1, @editor.quickfix.index
    assert_equal 'b.rb', @editor.filepath
  end

  def test_cprev_goes_back
    Rvim::Command.execute(@editor, Rvim::Command.parse(':vimgrep /TODO/ *.rb'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':cnext'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':cprev'))
    assert_equal 0, @editor.quickfix.index
    assert_equal 'a.rb', @editor.filepath
  end

  def test_cc_with_index
    Rvim::Command.execute(@editor, Rvim::Command.parse(':vimgrep! /TODO/ *.rb'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':cc 2'))
    assert_equal 1, @editor.quickfix.index
    assert_equal 'b.rb', @editor.filepath
  end

  def test_clist_shows_listing
    Rvim::Command.execute(@editor, Rvim::Command.parse(':vimgrep! /TODO/ *.rb'))
    Rvim::Command.execute(@editor, Rvim::Command.parse(':clist'))
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/a\.rb:2:/, body)
    assert_match(/b\.rb:2:/, body)
  end

  def test_cnext_empty_quickfix_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':cnext'))
    assert_match(/E42/, @editor.status_message.to_s)
  end

  def test_invalid_pattern_format_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':vimgrep TODO *.rb'))
    assert_match(/E682/, @editor.status_message.to_s)
  end
end
