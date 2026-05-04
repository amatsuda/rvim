# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

class TestZQ < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.config.editing_mode = :vi_command
  end

  def send_keys(*chars)
    chars.each do |ch|
      sym = @editor.send(:synthesize_key, ch).method_symbol
      @editor.update(Reline::Key.new(ch, sym, false))
    end
  end

  def test_ZQ_quits_without_saving
    Tempfile.create('zq') do |f|
      f.write("hello\n")
      f.close
      @editor.open(f.path)
      # Make a modification — ZQ should NOT save it.
      @editor.instance_variable_set(:@buffer_of_lines, [+'modified'])
      @editor.instance_variable_set(:@modified, true)

      send_keys('Z', 'Q')
      assert_equal true, @editor.instance_variable_get(:@quit)
      # File on disk untouched.
      assert_equal "hello\n", File.read(f.path)
    end
  end

  def test_ZQ_quits_with_no_filepath
    @editor.instance_variable_set(:@buffer_of_lines, [+'unsaved'])
    @editor.instance_variable_set(:@modified, true)
    send_keys('Z', 'Q')
    assert_equal true, @editor.instance_variable_get(:@quit)
  end

  def test_ZZ_still_saves_and_quits
    Tempfile.create('zz') do |f|
      f.write("hello\n")
      f.close
      @editor.open(f.path)
      @editor.instance_variable_set(:@buffer_of_lines, [+'after-ZZ'])
      @editor.instance_variable_set(:@modified, true)

      send_keys('Z', 'Z')
      assert_equal true, @editor.instance_variable_get(:@quit)
      assert_equal 'after-ZZ', File.read(f.path).chomp
    end
  end

  def test_Z_followed_by_other_key_does_nothing
    @editor.instance_variable_set(:@buffer_of_lines, [+'untouched'])
    send_keys('Z', 'x')
    refute @editor.instance_variable_get(:@quit)
    # Z prefix consumed; @waiting_proc cleared.
    assert_nil @editor.instance_variable_get(:@waiting_proc)
  end
end
