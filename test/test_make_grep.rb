# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'tmpdir'
require 'fileutils'

class TestErrorformatCompile < Test::Unit::TestCase
  def test_compiles_basic_format
    re = Rvim::Errorformat.compile('%f:%l:%c:%m')
    m = re.match('foo.rb:42:7:syntax error')
    assert_not_nil m
    assert_equal 'foo.rb', m[:f]
    assert_equal '42', m[:l]
    assert_equal '7', m[:c]
    assert_equal 'syntax error', m[:m]
  end

  def test_compiles_format_without_column
    re = Rvim::Errorformat.compile('%f:%l:%m')
    m = re.match('foo.rb:42:syntax error')
    assert_not_nil m
    assert_equal 'foo.rb', m[:f]
    assert_equal '42', m[:l]
    assert_equal 'syntax error', m[:m]
  end

  def test_literal_chars_escaped
    re = Rvim::Errorformat.compile('[%f] %l: %m')
    m = re.match('[foo.rb] 42: oops')
    assert_not_nil m
    assert_equal 'foo.rb', m[:f]
  end
end

class TestErrorformatParse < Test::Unit::TestCase
  def test_parse_with_multiple_formats
    output = "foo.rb:42:7:syntax error\nbar.rb:10:undefined var\n"
    entries = Rvim::Errorformat.parse(output, '%f:%l:%c:%m,%f:%l:%m')
    assert_equal 2, entries.size
    assert_equal 'foo.rb', entries[0].file
    assert_equal 42, entries[0].line
    assert_equal 7, entries[0].col
    assert_equal 'bar.rb', entries[1].file
    assert_equal 10, entries[1].line
    assert_equal 0, entries[1].col
    assert_equal 'undefined var', entries[1].text
  end

  def test_skips_unmatched_lines
    output = "foo.rb:42:7:err\nrandom text without colons\n"
    entries = Rvim::Errorformat.parse(output, '%f:%l:%c:%m')
    assert_equal 1, entries.size
  end

  def test_empty_output_no_entries
    assert_equal [], Rvim::Errorformat.parse('', '%f:%l:%m')
  end
end

class TestMakeGrepExec < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_grep_runs_and_populates_quickfix
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "foo\nTODO: fix this\nbar\n")
      File.write(File.join(dir, 'b.rb'), "no\nTODO: also\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.settings.set(:grepprg, 'grep -n')
      Rvim::Command.execute(@editor, Rvim::Command.parse(':grep! TODO *.rb'))
      assert_equal 2, @editor.quickfix.size
      files = @editor.quickfix.entries.map(&:file).sort
      assert_equal %w[a.rb b.rb], files
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_grep_no_match_sets_status
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "no matches here\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      Rvim::Command.execute(@editor, Rvim::Command.parse(':grep! XYZNEVER *.rb'))
      assert_match(/E480/, @editor.status_message.to_s)
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_grep_no_args_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':grep'))
    assert_match(/E471/, @editor.status_message.to_s)
  end

  def test_make_with_simulated_compiler_output
    Dir.mktmpdir do |dir|
      # Use 'sh -c "cat <<EOT"' as a fake compiler that emits errorformat-style lines
      script = File.join(dir, 'fake_make.sh')
      File.write(script, <<~SH)
        #!/bin/sh
        echo "foo.rb:42:7:syntax error"
        echo "bar.rb:10:undefined var"
        exit 1
      SH
      FileUtils.chmod(0o755, script)
      @editor.settings.set(:makeprg, script)
      Rvim::Command.execute(@editor, Rvim::Command.parse(':make!'))
      assert_equal 2, @editor.quickfix.size
      assert_equal 'foo.rb', @editor.quickfix.entries[0].file
      assert_equal 42, @editor.quickfix.entries[0].line
      assert_equal 7, @editor.quickfix.entries[0].col
    end
  end

  def test_make_no_errors_sets_status
    Dir.mktmpdir do |dir|
      script = File.join(dir, 'clean.sh')
      File.write(script, "#!/bin/sh\necho 'building...'\nexit 0\n")
      FileUtils.chmod(0o755, script)
      @editor.settings.set(:makeprg, script)
      Rvim::Command.execute(@editor, Rvim::Command.parse(':make!'))
      assert_equal 0, @editor.quickfix.size
      assert_match(/No errors/, @editor.status_message.to_s)
    end
  end

  def test_grepprg_with_dollar_star
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "TODO: x\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.settings.set(:grepprg, 'grep -n $* /dev/null')
      Rvim::Command.execute(@editor, Rvim::Command.parse(':grep! TODO a.rb'))
      assert_equal 1, @editor.quickfix.size
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_aliases_mp_gp_efm
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set mp=mymake'))
    assert_equal 'mymake', @editor.settings.get(:makeprg)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set gp=mygrep'))
    assert_equal 'mygrep', @editor.settings.get(:grepprg)
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set efm=%f:%l:%m'))
    assert_equal '%f:%l:%m', @editor.settings.get(:errorformat)
  end
end
