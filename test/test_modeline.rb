# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestModelineParse < Test::Unit::TestCase
  def test_parse_set_form
    assert_equal %w[ts=4 sw=4], Rvim::Modeline.parse('# vim: set ts=4 sw=4 :')
  end

  def test_parse_plain_form
    assert_equal %w[ts=4 sw=4], Rvim::Modeline.parse('# vim: ts=4 sw=4')
  end

  def test_parse_with_ex_prefix
    assert_equal %w[ts=4], Rvim::Modeline.parse('# ex: set ts=4 :')
  end

  def test_parse_no_match
    assert_nil Rvim::Modeline.parse('// just a normal comment')
  end

  def test_parse_handles_inline_text
    # vim modelines can be embedded; allow surrounding text
    assert_equal %w[ts=4], Rvim::Modeline.parse('-*- mode: ruby; vim: ts=4 :')
  end
end

class TestModelineApply < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_apply_sets_settings_on_buffer
    f = Tempfile.new(['ml', '.txt'])
    f.write("# vim: set ts=4 :\nbody\n")
    f.close
    @editor.open(f.path)
    assert_equal 4, @editor.settings.get(:tabstop)
  ensure
    f&.unlink
  end

  def test_apply_skipped_when_modeline_off
    f = Tempfile.new(['ml', '.txt'])
    f.write("# vim: set ts=4 :\nbody\n")
    f.close
    @editor.settings.set(:modeline, false)
    @editor.open(f.path)
    assert_equal 8, @editor.settings.get(:tabstop) # default
  ensure
    f&.unlink
  end

  def test_apply_scans_last_n_lines
    body = (1..20).map { |i| "line #{i}" }.join("\n") + "\n# vim: set ts=4 :\n"
    f = Tempfile.new(['ml', '.txt'])
    f.write(body)
    f.close
    @editor.open(f.path)
    assert_equal 4, @editor.settings.get(:tabstop)
  ensure
    f&.unlink
  end

  def test_apply_ignores_unknown_options
    f = Tempfile.new(['ml', '.txt'])
    f.write("# vim: set bogus=42 ts=4 :\nbody\n")
    f.close
    assert_nothing_raised do
      @editor.open(f.path)
    end
    assert_equal 4, @editor.settings.get(:tabstop)
  ensure
    f&.unlink
  end
end

class TestUndoFile < Test::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir
    @prev_xdg = ENV['XDG_CACHE_HOME']
    ENV['XDG_CACHE_HOME'] = @dir
  end

  def teardown
    ENV['XDG_CACHE_HOME'] = @prev_xdg
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def test_path_for_uses_xdg_cache_home
    p = Rvim::UndoFile.path_for('/some/file.rb')
    assert p.start_with?(@dir), "expected path to start with XDG_CACHE_HOME"
    assert p.include?('rvim/undo')
  end

  def test_write_and_read_roundtrip
    history = [[['line1'], 0, 0], [['line1', 'line2'], 1, 0]]
    Rvim::UndoFile.write('/tmp/example.rb', history, 1)
    assert_equal [history, 1], Rvim::UndoFile.read('/tmp/example.rb')
  end

  def test_read_missing_returns_nil
    assert_nil Rvim::UndoFile.read('/tmp/never_saved.rb')
  end

  def test_read_corrupt_returns_nil
    target = Rvim::UndoFile.path_for('/tmp/corrupt.rb')
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, 'not marshalled')
    assert_nil Rvim::UndoFile.read('/tmp/corrupt.rb')
  end

  def test_save_writes_undofile_when_setting_on
    f = Tempfile.new(['udf', '.txt'])
    f.write("hello\n")
    f.close
    editor = Rvim::Editor.new(Reline.core.config)
    editor.settings.set(:undofile, true)
    editor.open(f.path)
    editor.buffer_of_lines << +'world'
    editor.save
    sidecar = Rvim::UndoFile.path_for(f.path)
    assert File.exist?(sidecar), "expected sidecar at #{sidecar}"
  ensure
    f&.unlink
  end

  def test_open_loads_undofile_when_signature_matches
    f = Tempfile.new(['udf', '.txt'])
    f.write("first\n")
    f.close

    # Write an undo history matching the file content exactly
    history = [[['first'], 0, 0]]
    Rvim::UndoFile.write(f.path, history, 0)

    editor = Rvim::Editor.new(Reline.core.config)
    editor.settings.set(:undofile, true)
    editor.open(f.path)
    assert_equal history, editor.instance_variable_get(:@undo_redo_history)
  ensure
    f&.unlink
  end

  def test_open_skips_undofile_when_signature_mismatches
    f = Tempfile.new(['udf', '.txt'])
    f.write("changed\n")
    f.close
    history = [[['stale'], 0, 0]]
    Rvim::UndoFile.write(f.path, history, 0)

    editor = Rvim::Editor.new(Reline.core.config)
    editor.settings.set(:undofile, true)
    editor.open(f.path)
    refute_equal history, editor.instance_variable_get(:@undo_redo_history)
  ensure
    f&.unlink
  end
end
