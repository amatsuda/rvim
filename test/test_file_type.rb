# frozen_string_literal: true

require_relative 'test_helper'

class TestFileType < Test::Unit::TestCase
  def test_register_and_run
    called = false
    Rvim::FileType.register(:test_lang_a) do |_buf, _ed|
      called = true
    end
    Rvim::FileType.run(:test_lang_a, :buf, :ed)
    assert called
  end

  def test_run_unregistered_lang_is_noop
    assert_nothing_raised do
      Rvim::FileType.run(:totally_made_up, :buf, :ed)
    end
  end

  def test_run_with_nil_filetype_is_noop
    assert_nothing_raised do
      Rvim::FileType.run(nil, :buf, :ed)
    end
  end

  def test_multiple_registrations_run_in_order
    counter = 0
    Rvim::FileType.register(:test_lang_b) { |_b, _e| counter += 1 }
    Rvim::FileType.register(:test_lang_b) { |_b, _e| counter += 10 }
    Rvim::FileType.run(:test_lang_b, :buf, :ed)
    assert_equal 11, counter
  end
end
