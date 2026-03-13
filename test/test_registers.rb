# frozen_string_literal: true

require_relative 'test_helper'

class TestRegisters < Test::Unit::TestCase
  def setup
    @r = Rvim::Registers.new
  end

  def test_write_and_read
    @r.write('a', 'hello', :char)
    assert_equal 'hello', @r.read('a').text
    assert_equal :char, @r.read('a').kind
  end

  def test_write_mirrors_to_unnamed
    @r.write('a', 'hello', :char)
    assert_equal 'hello', @r.read('"').text
  end

  def test_uppercase_appends_charwise
    @r.write('a', 'foo', :char)
    @r.write('A', 'bar', :char)
    assert_equal 'foobar', @r.read('a').text
  end

  def test_uppercase_appends_linewise_with_newline
    @r.write('a', 'foo', :line)
    @r.write('A', 'bar', :line)
    assert_equal "foo\nbar", @r.read('a').text
  end

  def test_yank_history
    @r.write_yank_history('last', :char)
    assert_equal 'last', @r.read('0').text
  end

  def test_delete_history_shifts_ring
    @r.write_delete_history('first', :char)
    @r.write_delete_history('second', :char)
    @r.write_delete_history('third', :char)
    assert_equal 'third', @r.read('1').text
    assert_equal 'second', @r.read('2').text
    assert_equal 'first', @r.read('3').text
  end

  def test_read_unset_returns_nil
    assert_nil @r.read('z')
  end
end
