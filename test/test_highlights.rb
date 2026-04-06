# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class TestHighlightsRegistry < Test::Unit::TestCase
  def setup
    Rvim::Highlights.reset_to_defaults!
  end

  def teardown
    Rvim::Highlights.reset_to_defaults!
  end

  def test_default_groups_exist
    %w[Normal Comment String Number Keyword Constant LineNr StatusLine Search].each do |g|
      assert_not_nil Rvim::Highlights.get(g), "expected default for #{g}"
    end
  end

  def test_set_updates_a_group
    Rvim::Highlights.set('Comment', fg: 'green', bold: true)
    attr = Rvim::Highlights.get('Comment')
    assert_equal 'green', attr.fg
    assert_equal true, attr.bold
  end

  def test_set_preserves_unspecified_fields
    Rvim::Highlights.set('Comment', fg: 'red')
    attr = Rvim::Highlights.get('Comment')
    assert_equal 'red', attr.fg
    # bg remains nil (default Comment has no bg)
    assert_nil attr.bg
  end

  def test_clear_resets_group
    Rvim::Highlights.set('Comment', fg: 'red')
    Rvim::Highlights.clear('Comment')
    attr = Rvim::Highlights.get('Comment')
    assert_nil attr.fg
  end

  def test_reset_to_defaults
    Rvim::Highlights.set('Comment', fg: 'red')
    Rvim::Highlights.reset_to_defaults!
    assert_equal 'cyan', Rvim::Highlights.get('Comment').fg
  end

  def test_ansi_prefix_emits_fg_code
    Rvim::Highlights.set('Comment', fg: 'red')
    out = Rvim::Highlights.ansi_prefix('Comment')
    assert_equal "\e[31m", out
  end

  def test_ansi_prefix_with_bold_and_color
    Rvim::Highlights.set('Comment', fg: 'red', bold: true)
    out = Rvim::Highlights.ansi_prefix('Comment')
    assert out.include?("\e[1m")
    assert out.include?("\e[31m")
  end

  def test_ansi_suffix_resets_attributes
    Rvim::Highlights.set('Comment', fg: 'red', bold: true)
    out = Rvim::Highlights.ansi_suffix('Comment')
    assert out.include?("\e[39m")
    assert out.include?("\e[22m")
  end

  def test_wrap_combines_prefix_and_suffix
    Rvim::Highlights.set('Comment', fg: 'red')
    out = Rvim::Highlights.wrap('Comment', 'hello')
    assert_equal "\e[31mhello\e[39m", out
  end
end

class TestHighlightCommands < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Highlights.reset_to_defaults!
  end

  def teardown
    Rvim::Highlights.reset_to_defaults!
  end

  def test_hi_sets_fg
    Rvim::Command.execute(@editor, Rvim::Command.parse(':hi Comment ctermfg=red'))
    assert_equal 'red', Rvim::Highlights.get('Comment').fg
  end

  def test_hi_sets_attributes
    Rvim::Command.execute(@editor, Rvim::Command.parse(':hi Comment cterm=bold,underline'))
    attr = Rvim::Highlights.get('Comment')
    assert_equal true, attr.bold
    assert_equal true, attr.underline
  end

  def test_hi_clear_specific_group
    Rvim::Highlights.set('Comment', fg: 'red')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':hi clear Comment'))
    assert_nil Rvim::Highlights.get('Comment').fg
  end

  def test_hi_clear_all
    Rvim::Highlights.set('Comment', fg: 'red')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':hi clear'))
    # back to default cyan
    assert_equal 'cyan', Rvim::Highlights.get('Comment').fg
  end

  def test_hi_no_args_lists_all
    Rvim::Command.execute(@editor, Rvim::Command.parse(':hi'))
    refute_nil @editor.list_view
    body = @editor.list_view.lines.join("\n")
    assert_match(/Comment/, body)
    assert_match(/cyan/, body)
  end

  def test_colorscheme_default_resets
    Rvim::Highlights.set('Comment', fg: 'red')
    Rvim::Command.execute(@editor, Rvim::Command.parse(':colorscheme default'))
    assert_equal 'cyan', Rvim::Highlights.get('Comment').fg
  end

  def test_colorscheme_unknown_sets_status
    Rvim::Command.execute(@editor, Rvim::Command.parse(':colorscheme nonexistent'))
    assert_match(/E185/, @editor.status_message.to_s)
  end

  def test_colorscheme_sources_user_file
    Dir.mktmpdir do |dir|
      colors = File.join(dir, '.config', 'rvim', 'colors')
      FileUtils.mkdir_p(colors)
      File.write(File.join(colors, 'mine.vim'), "hi Comment ctermfg=blue\n")

      saved = ENV['HOME']
      ENV['HOME'] = dir
      Rvim::Command.execute(@editor, Rvim::Command.parse(':colorscheme mine'))
      assert_equal 'blue', Rvim::Highlights.get('Comment').fg
    ensure
      ENV['HOME'] = saved
    end
  end
end
