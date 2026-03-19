# frozen_string_literal: true

require_relative 'test_helper'

class TestSettings < Test::Unit::TestCase
  def setup
    @s = Rvim::Settings.new
  end

  def test_defaults
    assert_equal true, @s.get(:hlsearch)
    assert_equal 2, @s.get(:shiftwidth)
    assert_equal false, @s.get(:number)
    assert_equal :auto, @s.get(:syntax)
  end

  def test_set_and_get
    @s.set(:number, true)
    assert_equal true, @s.get(:number)
    @s.set(:shiftwidth, 4)
    assert_equal 4, @s.get(:shiftwidth)
  end

  def test_alias_resolution
    @s.set('nu', true)
    assert_equal true, @s.get(:number)
    @s.set('sw', 8)
    assert_equal 8, @s.get(:shiftwidth)
  end

  def test_known_predicate
    assert @s.known?(:hlsearch)
    assert @s.known?('hls')
    assert @s.known?('sw')
    assert !@s.known?(:nonsense)
  end
end
