# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'tmpdir'

class TestSourceCommand < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_source_runs_set_commands
    f = Tempfile.new(['rc', '.rvimrc'])
    f.write("set number\nset shiftwidth=8\n")
    f.close
    @editor.source(f.path)
    assert_equal true, @editor.settings.get(:number)
    assert_equal 8, @editor.settings.get(:shiftwidth)
  ensure
    f&.unlink
  end

  def test_source_skips_blank_and_comment_lines
    f = Tempfile.new(['rc', '.rvimrc'])
    f.write(<<~RC)

      " Vim-style comment
      # Hash comment

      set number
    RC
    f.close
    @editor.source(f.path)
    assert_equal true, @editor.settings.get(:number)
    assert_nil @editor.status_message
  ensure
    f&.unlink
  end

  def test_source_missing_file_sets_status
    @editor.source('/tmp/rvim_does_not_exist_zzz')
    assert_match(/E484/, @editor.status_message.to_s)
  end

  def test_source_recursion_depth_limited
    f = Tempfile.new(['rc', '.rvimrc'])
    f.write("source #{f.path}\n")
    f.close
    @editor.source(f.path)
    assert_match(/nested too deep/, @editor.status_message.to_s)
  ensure
    f&.unlink
  end

  def test_source_continues_past_unknown_command
    f = Tempfile.new(['rc', '.rvimrc'])
    f.write("nosuchverb\nset number\n")
    f.close
    @editor.source(f.path)
    assert_equal true, @editor.settings.get(:number)
  ensure
    f&.unlink
  end
end

class TestIgnorecaseSmartcase < Test::Unit::TestCase
  def test_compile_ignorecase
    re = Rvim::Search.compile('foo', ignorecase: true)
    assert re.match?('FOO')
  end

  def test_scan_ignorecase
    m = Rvim::Search.scan(['Foo', 'foo', 'FOO'], 'foo', ignorecase: true)
    assert_equal 3, m.size
  end

  def test_effective_ignorecase_with_smartcase
    assert_equal true,  Rvim::Search.effective_ignorecase('foo', ignorecase: true,  smartcase: true)
    assert_equal false, Rvim::Search.effective_ignorecase('Foo', ignorecase: true,  smartcase: true)
    assert_equal true,  Rvim::Search.effective_ignorecase('Foo', ignorecase: true,  smartcase: false)
    assert_equal false, Rvim::Search.effective_ignorecase('foo', ignorecase: false, smartcase: true)
  end

  def test_settings_ignorecase_alias
    s = Rvim::Settings.new
    s.set(:ic, true)
    assert_equal true, s.get(:ignorecase)
  end

  def test_settings_smartcase_alias
    s = Rvim::Settings.new
    s.set(:scs, true)
    assert_equal true, s.get(:smartcase)
  end
end

class TestExHistory < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    f = Tempfile.new(['x', '.txt'])
    f.write("a\nb\n")
    f.close
    @path = f.path
    @editor.open(@path)
  end

  def teardown
    File.unlink(@path) if @path && File.exist?(@path)
  end

  def k(s, sym = :ed_insert)
    Reline::Key.new(s, sym, false)
  end

  def submit(line)
    @editor.send(:rvim_enter_command_mode, nil)
    line.each_char { |c| @editor.send(:process_prompt_key, k(c)) }
    @editor.send(:process_prompt_key, k("\r"))
  end

  def test_history_pushed_on_enter
    submit('set number')
    submit('set shiftwidth=4')
    assert_equal ['set number', 'set shiftwidth=4'], @editor.ex_history
  end

  def test_history_dedupes_consecutive
    submit('set number')
    submit('set number')
    assert_equal ['set number'], @editor.ex_history
  end

  def test_up_recall_oldest_then_back_to_draft
    submit('set number')
    submit('set shiftwidth=4')
    @editor.send(:rvim_enter_command_mode, nil)
    @editor.send(:process_prompt_key, k("\e[A", :ed_prev_history))
    assert_equal 'set shiftwidth=4', @editor.prompt_buffer
    @editor.send(:process_prompt_key, k("\e[A", :ed_prev_history))
    assert_equal 'set number', @editor.prompt_buffer
    @editor.send(:process_prompt_key, k("\e[B", :ed_next_history))
    assert_equal 'set shiftwidth=4', @editor.prompt_buffer
    @editor.send(:process_prompt_key, k("\e[B", :ed_next_history))
    assert_equal '', @editor.prompt_buffer
  end

  def test_up_preserves_typed_draft
    submit('foo')
    @editor.send(:rvim_enter_command_mode, nil)
    'bar'.each_char { |c| @editor.send(:process_prompt_key, k(c)) }
    @editor.send(:process_prompt_key, k("\e[A", :ed_prev_history))
    assert_equal 'foo', @editor.prompt_buffer
    @editor.send(:process_prompt_key, k("\e[B", :ed_next_history))
    assert_equal 'bar', @editor.prompt_buffer
  end
end

class TestInitVim < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_source_runs_init_vim_content
    f = Tempfile.new(['init', '.vim'])
    f.write("set number\nset shiftwidth=8\n")
    f.close
    @editor.source(f.path)
    assert_equal true, @editor.settings.get(:number)
    assert_equal 8, @editor.settings.get(:shiftwidth)
  ensure
    f&.unlink
  end

  def test_init_vim_overrides_rvimrc_when_sourced_second
    rvimrc = Tempfile.new(['rc', '.rvimrc'])
    rvimrc.write("set shiftwidth=2\n")
    rvimrc.close
    init_vim = Tempfile.new(['init', '.vim'])
    init_vim.write("set shiftwidth=8\n")
    init_vim.close
    @editor.source(rvimrc.path)
    @editor.source(init_vim.path)
    assert_equal 8, @editor.settings.get(:shiftwidth)
  ensure
    rvimrc&.unlink
    init_vim&.unlink
  end

  def test_init_vim_path_uses_xdg_config_home
    Dir.mktmpdir do |dir|
      saved = ENV['XDG_CONFIG_HOME']
      ENV['XDG_CONFIG_HOME'] = dir
      assert_equal File.join(dir, 'rvim', 'init.vim'), Rvim::Editor.init_vim_path
    ensure
      ENV['XDG_CONFIG_HOME'] = saved
    end
  end

  def test_init_vim_path_falls_back_to_dot_config
    saved = ENV['XDG_CONFIG_HOME']
    ENV['XDG_CONFIG_HOME'] = nil
    assert_equal File.expand_path('~/.config/rvim/init.vim'), Rvim::Editor.init_vim_path
  ensure
    ENV['XDG_CONFIG_HOME'] = saved
  end

  def test_init_vim_path_treats_empty_xdg_as_unset
    saved = ENV['XDG_CONFIG_HOME']
    ENV['XDG_CONFIG_HOME'] = ''
    assert_equal File.expand_path('~/.config/rvim/init.vim'), Rvim::Editor.init_vim_path
  ensure
    ENV['XDG_CONFIG_HOME'] = saved
  end
end
