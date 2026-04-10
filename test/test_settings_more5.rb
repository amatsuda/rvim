# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'tmpdir'

class TestAutowrite < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_off_by_default
    assert_equal false, @editor.settings.get(:autowrite)
  end

  def test_aw_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set aw'))
    assert_equal true, @editor.settings.get(:autowrite)
  end

  def test_cycle_buffer_writes_when_aw_on
    Dir.mktmpdir do |dir|
      a = File.join(dir, 'a.txt')
      b = File.join(dir, 'b.txt')
      File.write(a, "first\n")
      File.write(b, "second\n")
      @editor.open(a)
      @editor.open(b)

      # Switch back to a, modify
      @editor.swap_to_buffer(@editor.buffers.values.find { |buf| buf.filepath == a })
      @editor.buffer_of_lines[0] = +'changed'
      @editor.modified = true

      @editor.settings.set(:autowrite, true)
      @editor.cycle_buffer(+1)

      contents = File.read(a)
      assert_match(/changed/, contents)
    end
  end

  def test_cycle_buffer_no_write_when_aw_off
    Dir.mktmpdir do |dir|
      a = File.join(dir, 'a.txt')
      b = File.join(dir, 'b.txt')
      File.write(a, "first\n")
      File.write(b, "second\n")
      @editor.open(a)
      @editor.open(b)
      @editor.swap_to_buffer(@editor.buffers.values.find { |buf| buf.filepath == a })
      @editor.buffer_of_lines[0] = +'changed'
      @editor.modified = true

      @editor.settings.set(:autowrite, false)
      @editor.cycle_buffer(+1)

      contents = File.read(a)
      refute_match(/changed/, contents)
    end
  end
end

class TestEqualalways < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    buf = Rvim::Buffer.new(1, nil)
    @editor.instance_variable_set(:@current_buffer, buf)
    initial = Rvim::Window.new(buf)
    initial.extra_rows = 5
    @editor.instance_variable_set(:@windows, [initial])
    @editor.instance_variable_set(:@current_window, initial)
  end

  def test_default_equalalways_resets_extras_on_split
    @editor.settings.set(:equalalways, true)
    @editor.split_horizontal
    @editor.windows.each { |w| assert_equal 0, w.extra_rows }
  end

  def test_equalalways_off_keeps_extras
    @editor.settings.set(:equalalways, false)
    @editor.split_horizontal
    # Initial window's extra_rows should still be 5
    assert_equal 5, @editor.windows.find { |w| w != @editor.current_window }.extra_rows
  end
end

class TestHistorySetting < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_100
    assert_equal 100, @editor.settings.get(:history)
  end

  def test_history_caps_ex_history_size
    @editor.settings.set(:history, 3)
    %w[a b c d e].each { |c| @editor.send(:push_ex_history, c) }
    assert_equal 3, @editor.ex_history.size
    assert_equal %w[c d e], @editor.ex_history
  end

  def test_hi_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set hi=20'))
    assert_equal 20, @editor.settings.get(:history)
  end

  def test_zero_or_negative_falls_back_to_default
    @editor.settings.set(:history, 0)
    50.times { |i| @editor.send(:push_ex_history, i.to_s) }
    # With history=0 we fall back to EX_HISTORY_MAX (100), so all 50 fit
    assert_equal 50, @editor.ex_history.size
  end
end
