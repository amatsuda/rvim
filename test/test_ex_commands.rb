# frozen_string_literal: true

require_relative 'test_helper'

class TestGenericRangePrefix < Test::Unit::TestCase
  def test_strips_range_for_known_verb
    parsed = Rvim::Command.parse(':5,10delete')
    assert_equal :delete, parsed.verb
    assert_equal [5, 10], parsed.range
  end

  def test_whole_range
    parsed = Rvim::Command.parse(':%yank')
    assert_equal :yank, parsed.verb
    assert_equal :whole, parsed.range
  end

  def test_visual_range
    parsed = Rvim::Command.parse(":'<,'>delete")
    assert_equal :delete, parsed.verb
    assert_equal :visual, parsed.range
  end

  def test_no_range_leaves_nil
    parsed = Rvim::Command.parse(':delete')
    assert_equal :delete, parsed.verb
    assert_nil parsed.range
  end

  def test_substitute_keeps_its_own_range_parsing
    parsed = Rvim::Command.parse(':5,10s/foo/bar/g')
    assert_equal :sub, parsed.verb
    assert_equal [5, 10], parsed.range
  end
end

class TestExDeleteYankPut < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def buf(*lines, line: 0)
    @editor.instance_variable_set(:@buffer_of_lines, lines.map { |l| +l })
    @editor.instance_variable_set(:@line_index, line)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_delete_with_range
    buf('a', 'b', 'c', 'd')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':2,3delete'))
    assert_equal ['a', 'd'], @editor.buffer_of_lines
  end

  def test_delete_count_arg
    buf('a', 'b', 'c', 'd', line: 1)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':delete 2'))
    assert_equal ['a', 'd'], @editor.buffer_of_lines
  end

  def test_delete_writes_to_unnamed_register
    buf('a', 'b', 'c')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':2delete'))
    assert_equal 'b', @editor.read_register('"').text
  end

  def test_yank_does_not_remove
    buf('a', 'b', 'c', line: 0)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':2yank'))
    assert_equal 3, @editor.buffer_of_lines.size
    assert_equal 'b', @editor.read_register('"').text
  end

  def test_put_inserts_register_below_current
    buf('first', 'second', line: 0)
    @editor.send(:write_register, 'pasted', :line, register: nil)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':put'))
    assert_equal ['first', 'pasted', 'second'], @editor.buffer_of_lines
  end

  def test_put_named_register
    buf('first', line: 0)
    @editor.send(:write_register, 'from a', :line, register: 'a')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':put a'))
    assert_equal ['first', 'from a'], @editor.buffer_of_lines
  end

  def test_put_with_range
    buf('a', 'b', 'c', 'd', line: 0)
    @editor.send(:write_register, 'X', :line, register: nil)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':2put'))
    # Insert AFTER line 2 (1-based) → after 'b'
    assert_equal ['a', 'b', 'X', 'c', 'd'], @editor.buffer_of_lines
  end
end

class TestExMoveCopy < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def buf(*lines, line: 0)
    @editor.instance_variable_set(:@buffer_of_lines, lines.map { |l| +l })
    @editor.instance_variable_set(:@line_index, line)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_move_range_to_target
    buf('a', 'b', 'c', 'd', 'e')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':2,3move 5'))
    # Move lines 2-3 (b,c) to after line 5 (e). Result: a, d, e, b, c
    assert_equal ['a', 'd', 'e', 'b', 'c'], @editor.buffer_of_lines
  end

  def test_copy_range_to_target
    buf('a', 'b', 'c')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':1,2copy 3'))
    assert_equal ['a', 'b', 'c', 'a', 'b'], @editor.buffer_of_lines
  end

  def test_t_alias_for_copy
    buf('a', 'b')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':1t2'))
    assert_equal ['a', 'b', 'a'], @editor.buffer_of_lines
  end
end

class TestExJoin < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def buf(*lines, line: 0)
    @editor.instance_variable_set(:@buffer_of_lines, lines.map { |l| +l })
    @editor.instance_variable_set(:@line_index, line)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_join_range
    buf('hello', 'world', 'now')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':1,3join'))
    assert_equal ['hello world now'], @editor.buffer_of_lines
  end

  def test_join_strips_leading_whitespace_from_followers
    buf('hello', '   world')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':1,2join'))
    assert_equal ['hello world'], @editor.buffer_of_lines
  end

  def test_join_bang_no_space
    buf('hello', 'world')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':1,2join!'))
    assert_equal ['helloworld'], @editor.buffer_of_lines
  end

  def test_join_default_joins_current_and_next
    buf('a', 'b', 'c', line: 0)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':join'))
    assert_equal ['a b', 'c'], @editor.buffer_of_lines
  end
end

class TestExMisc < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_nohlsearch_clears_search
    @editor.instance_variable_set(:@buffer_of_lines, ['foo bar foo'])
    @editor.instance_variable_set(:@search_pattern, 'foo')
    @editor.instance_variable_set(:@search_matches, [[0, 0, 3], [0, 8, 11]])
    Rvim::Command.execute(@editor, Rvim::Command.parse(':noh'))
    assert_nil @editor.search_pattern
    assert_equal [], @editor.search_matches
  end

  def test_retab_replaces_tabs_with_spaces
    @editor.instance_variable_set(:@buffer_of_lines, [+"a\tb\tc"])
    @editor.settings.set(:shiftwidth, 4)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':retab'))
    assert_equal ['a    b    c'], @editor.buffer_of_lines
  end

  def test_retab_with_explicit_width
    @editor.instance_variable_set(:@buffer_of_lines, [+"a\tb"])
    Rvim::Command.execute(@editor, Rvim::Command.parse(':retab 2'))
    assert_equal ['a  b'], @editor.buffer_of_lines
  end

  def test_pwd_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':pwd'))
    assert_equal Dir.pwd, @editor.status_message
  end

  def test_cd_changes_directory
    require 'tmpdir'
    saved = Dir.pwd
    Dir.mktmpdir do |dir|
      Rvim::Command.execute(@editor, Rvim::Command.parse(":cd #{dir}"))
      assert_equal File.realpath(dir), File.realpath(Dir.pwd)
    end
  ensure
    Dir.chdir(saved)
  end

  def test_cd_no_arg_goes_home
    saved = Dir.pwd
    Rvim::Command.execute(@editor, Rvim::Command.parse(':cd'))
    assert_equal Dir.home, Dir.pwd
  ensure
    Dir.chdir(saved)
  end
end
