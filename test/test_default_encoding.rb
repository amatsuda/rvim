# frozen_string_literal: true

require_relative 'test_helper'

# Loading rvim should pin the process encodings to UTF-8 so file IO,
# backticks, and Open3 hand us correctly-labeled strings by default.
class TestDefaultEncoding < Test::Unit::TestCase
  def test_default_external_is_utf8
    assert_equal Encoding::UTF_8, Encoding.default_external
  end

  def test_default_internal_is_utf8
    assert_equal Encoding::UTF_8, Encoding.default_internal
  end

  def test_backticks_return_utf8_labeled_strings
    out = `echo hi`
    assert_equal Encoding::UTF_8, out.encoding
  end

  def test_file_read_returns_utf8_labeled_string
    Tempfile.create('rvim-enc') do |f|
      f.write('hello')
      f.close
      assert_equal Encoding::UTF_8, File.read(f.path).encoding
    end
  end
end
