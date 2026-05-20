# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

# Opening a file of a known filetype should source the matching
# runtime/ftplugin/<ft>.vim — which sets `:setlocal commentstring`
# to the right value so the built-in gc/gcc operator uses
# language-appropriate comment chars.

class TestRuntimeFtplugin < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_bundled_runtime(@editor)
  end

  EXPECTED = {
    '.rb'   => '# %s',
    '.lua'  => '-- %s',
    '.js'   => '// %s',
    '.ts'   => '// %s',
    '.go'   => '// %s',
    '.rs'   => '// %s',
    '.py'   => '# %s',
    '.css'  => '/* %s */',
    '.html' => '<!-- %s -->',
    '.md'   => '<!-- %s -->',
    '.sh'   => '# %s',
    '.sql'  => '-- %s',
    '.vim'  => '" %s',
    '.json' => '// %s',
  }.freeze

  def test_each_filetype_gets_correct_commentstring
    EXPECTED.each do |ext, expected|
      Tempfile.create(['sample', ext]) do |tf|
        tf.write("body\n")
        tf.flush
        @editor.open(tf.path)
        assert_equal expected, @editor.settings.get(:commentstring),
                     "expected #{expected.inspect} for #{ext}"
      end
    end
  end

  def test_set_value_supports_escaped_space
    # :set parser used to split on any whitespace, dropping the rest
    # of "commentstring=#\\ %s" after the space. The escaped form is
    # vim's standard way to embed a literal space.
    parsed = Rvim::Command.parse(':setlocal commentstring=--\\ %s')
    assert_equal [['commentstring', '-- %s']], parsed.set_options
  end

  def test_basename_dispatch_recognizes_dockerfile_and_friends
    %w[Gemfile Rakefile Dockerfile Makefile CMakeLists.txt].each do |name|
      ft = Rvim::Syntax.detect_language("/tmp/#{name}")
      refute_nil ft, "expected basename detection for #{name}"
    end
  end

  def test_shebang_dispatch
    Tempfile.create(['noext', '']) do |tf|
      tf.write("#!/usr/bin/env ruby\nputs 1\n")
      tf.flush
      ft = Rvim::Syntax.detect_language(tf.path)
      assert_equal :ruby, ft
    end
  end
end
