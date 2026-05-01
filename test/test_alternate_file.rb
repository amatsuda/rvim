# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestAlternateFile < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @file_a = Tempfile.create(['a-', '.txt']).tap { |f| f.write("aaa\n"); f.close }
    @file_b = Tempfile.create(['b-', '.txt']).tap { |f| f.write("bbb\n"); f.close }
  end

  def teardown
    File.unlink(@file_a.path) if File.exist?(@file_a.path)
    File.unlink(@file_b.path) if File.exist?(@file_b.path)
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_ctrl_caret_swaps_to_alternate
    @editor.open(@file_a.path)
    @editor.open(@file_b.path)
    assert_equal @file_b.path, @editor.filepath

    send_keys(0x1E.chr) # Ctrl-^
    assert_equal @file_a.path, @editor.filepath
  end

  def test_ctrl_caret_toggles_back_and_forth
    @editor.open(@file_a.path)
    @editor.open(@file_b.path)

    send_keys(0x1E.chr)
    assert_equal @file_a.path, @editor.filepath

    send_keys(0x1E.chr)
    assert_equal @file_b.path, @editor.filepath
  end

  def test_no_alternate_warns
    @editor.open(@file_a.path)
    send_keys(0x1E.chr)
    assert_match(/E23/, @editor.status_message.to_s)
  end

  def test_ctrl_caret_loads_alternate_when_buffer_unloaded
    @editor.open(@file_a.path)
    # Manually set alternate to a path that isn't in buffer list yet.
    @editor.alternate_filepath = @file_b.path
    send_keys(0x1E.chr)
    assert_equal @file_b.path, @editor.filepath
  end
end
