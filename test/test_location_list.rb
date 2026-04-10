# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'tmpdir'
require 'fileutils'

class TestLocationListStorage < Test::Unit::TestCase
  def test_window_has_location_list
    buf = Rvim::Buffer.new(1, nil)
    win = Rvim::Window.new(buf)
    assert_kind_of Rvim::Quickfix, win.location_list
    assert_equal true, win.location_list.empty?
  end

  def test_each_window_has_independent_list
    buf = Rvim::Buffer.new(1, nil)
    a = Rvim::Window.new(buf)
    b = Rvim::Window.new(buf)
    refute_equal a.location_list.object_id, b.location_list.object_id
  end
end

class TestLvimgrep < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_lvimgrep_populates_location_list
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "TODO: a\nfoo\nTODO: a2\n")
      File.write(File.join(dir, 'b.rb'), "TODO: b\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.open(File.join(dir, 'a.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lvimgrep! /TODO/ *.rb'))
      assert_equal 3, @editor.current_window.location_list.size
      # Quickfix list (global) should be untouched
      assert_equal 0, @editor.quickfix.size
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_lvimgrep_no_match
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "no match\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.open(File.join(dir, 'a.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lvimgrep! /XYZNEVER/ *.rb'))
      assert_match(/E480/, @editor.status_message.to_s)
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_lnext_navigates_location_list
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "TODO: 1\nTODO: 2\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.open(File.join(dir, 'a.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lvimgrep! /TODO/ *.rb'))
      assert_equal 0, @editor.current_window.location_list.index
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lnext'))
      assert_equal 1, @editor.current_window.location_list.index
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_lprev_goes_back
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "TODO: 1\nTODO: 2\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.open(File.join(dir, 'a.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lvimgrep! /TODO/ *.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lnext'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lprev'))
      assert_equal 0, @editor.current_window.location_list.index
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_ll_with_index
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "TODO: 1\nTODO: 2\nTODO: 3\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.open(File.join(dir, 'a.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lvimgrep! /TODO/ *.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':ll 3'))
      assert_equal 2, @editor.current_window.location_list.index
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_llist_shows_listing
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "TODO: x\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.open(File.join(dir, 'a.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lvimgrep! /TODO/ *.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':llist'))
      refute_nil @editor.list_view
      body = @editor.list_view.lines.join("\n")
      assert_match(/a\.rb:1:/, body)
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_lnext_with_empty_list_sets_status
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "")
      @editor.open(File.join(dir, 'a.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lnext'))
      assert_match(/E776/, @editor.status_message.to_s)
    end
  end
end

class TestLgrepLmake < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_lgrep_populates_location_list
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.rb'), "TODO: line1\nbar\n")
      saved = Dir.pwd
      Dir.chdir(dir)
      @editor.open(File.join(dir, 'a.rb'))
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lgrep! TODO *.rb'))
      assert_equal 1, @editor.current_window.location_list.size
      assert_equal 0, @editor.quickfix.size
    ensure
      Dir.chdir(saved) if saved
    end
  end

  def test_lmake_runs_makeprg
    Dir.mktmpdir do |dir|
      script = File.join(dir, 'fake.sh')
      File.write(script, "#!/bin/sh\necho 'foo.rb:1:err'\nexit 1\n")
      FileUtils.chmod(0o755, script)
      File.write(File.join(dir, 'a.rb'), '')
      @editor.open(File.join(dir, 'a.rb'))
      @editor.settings.set(:makeprg, script)
      Rvim::Command.execute(@editor, Rvim::Command.parse(':lmake!'))
      assert_equal 1, @editor.current_window.location_list.size
      assert_equal 'foo.rb', @editor.current_window.location_list.entries[0].file
    end
  end
end
