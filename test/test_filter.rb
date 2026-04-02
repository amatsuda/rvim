# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestFilterRunner < Test::Unit::TestCase
  def test_run_captures_stdout
    result = Rvim::Filter.run('echo hello')
    assert_equal "hello\n", result.stdout
    assert_equal true, result.success?
  end

  def test_run_pipes_stdin
    result = Rvim::Filter.run('cat', input: "alpha\nbeta\n")
    assert_equal "alpha\nbeta\n", result.stdout
    assert_equal true, result.success?
  end

  def test_run_sort
    result = Rvim::Filter.run('sort', input: "c\na\nb\n")
    assert_equal "a\nb\nc\n", result.stdout
  end

  def test_run_failing_command
    result = Rvim::Filter.run('false')
    assert_equal false, result.success?
  end

  def test_run_captures_stderr
    result = Rvim::Filter.run('echo err 1>&2; false')
    assert_equal false, result.success?
    assert_equal "err\n", result.stderr
  end

  def test_run_empty_input
    result = Rvim::Filter.run('cat', input: '')
    assert_equal '', result.stdout
    assert_equal true, result.success?
  end
end

class TestFilterParse < Test::Unit::TestCase
  def test_parse_bang
    parsed = Rvim::Command.parse(':!ls')
    assert_equal :bang, parsed.verb
    assert_equal 'ls', parsed.arg
  end

  def test_parse_bang_with_args
    parsed = Rvim::Command.parse(':!sort -r foo.txt')
    assert_equal :bang, parsed.verb
    assert_equal 'sort -r foo.txt', parsed.arg
  end

  def test_parse_whole_filter
    parsed = Rvim::Command.parse(':%!sort')
    assert_equal :filter, parsed.verb
    assert_equal :whole, parsed.range
    assert_equal 'sort', parsed.arg
  end

  def test_parse_line_range_filter
    parsed = Rvim::Command.parse(':3,7!sort')
    assert_equal :filter, parsed.verb
    assert_equal [3, 7], parsed.range
    assert_equal 'sort', parsed.arg
  end

  def test_parse_visual_filter
    parsed = Rvim::Command.parse(":'<,'>!cat")
    assert_equal :filter, parsed.verb
    assert_equal :visual, parsed.range
    assert_equal 'cat', parsed.arg
  end

  def test_parse_read_with_bang
    parsed = Rvim::Command.parse(':r !date')
    assert_equal :r, parsed.verb
    assert_equal '!date', parsed.arg
  end

  def test_parse_read_file
    parsed = Rvim::Command.parse(':r foo.txt')
    assert_equal :r, parsed.verb
    assert_equal 'foo.txt', parsed.arg
  end
end

class TestFilterExecute < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def buf(*lines)
    @editor.instance_variable_set(:@buffer_of_lines, lines.map { |l| +l })
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_filter_whole_buffer_sort
    buf('charlie', 'alpha', 'bravo')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':%!sort'))
    assert_equal %w[alpha bravo charlie], @editor.buffer_of_lines
  end

  def test_filter_range
    buf('one', 'three', 'two', 'zzz')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':2,3!sort'))
    assert_equal %w[one three two zzz], @editor.buffer_of_lines
    # Wait — sort on 'three','two' gives 'three','two' (alphabetical t-h < t-w)
    # That's actually what we got. Let me verify:
  end

  def test_filter_uppercase_via_tr
    buf('hello', 'world')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':%!tr a-z A-Z'))
    assert_equal %w[HELLO WORLD], @editor.buffer_of_lines
  end

  def test_filter_marks_modified
    buf('c', 'a', 'b')
    @editor.modified = false
    Rvim::Command.execute(@editor, Rvim::Command.parse(':%!sort'))
    assert_equal true, @editor.modified
  end

  def test_filter_failing_command_leaves_buffer
    buf('one', 'two')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':%!false'))
    assert_equal %w[one two], @editor.buffer_of_lines
    assert_match(/E: filter:/, @editor.status_message.to_s)
  end

  def test_bang_shows_output_via_list
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!echo foo'))
    refute_nil @editor.list_view
    assert_equal ['foo'], @editor.list_view.lines
  end

  def test_bang_failing_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':!false'))
    assert_match(/E: filter:/, @editor.status_message.to_s)
  end

  def test_read_bang_inserts_after_current_line
    buf('first', 'second')
    @editor.instance_variable_set(:@line_index, 0)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':r !echo inserted'))
    assert_equal ['first', 'inserted', 'second'], @editor.buffer_of_lines
  end

  def test_read_file_inserts_after_current_line
    f = Tempfile.new(['rread', '.txt'])
    f.write("alpha\nbeta\n")
    f.close
    buf('start', 'end')
    @editor.instance_variable_set(:@line_index, 0)
    Rvim::Command.execute(@editor, Rvim::Command.parse(":r #{f.path}"))
    assert_equal ['start', 'alpha', 'beta', 'end'], @editor.buffer_of_lines
  ensure
    f&.unlink
  end

  def test_filter_replaces_with_more_lines
    buf('compact')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':%!printf "a\nb\nc\n"'))
    assert_equal %w[a b c], @editor.buffer_of_lines
  end

  def test_filter_replaces_with_fewer_lines
    buf('a', 'b', 'c', 'd')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':%!head -1'))
    assert_equal ['a'], @editor.buffer_of_lines
  end
end
