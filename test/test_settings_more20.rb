# frozen_string_literal: true

require_relative 'test_helper'

class TestTimeoutSettings < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_timeout_default_on
    assert_equal true, @editor.settings.get(:timeout)
  end

  def test_to_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set notimeout'))
    assert_equal false, @editor.settings.get(:timeout)
  end

  def test_timeoutlen_default
    assert_equal 1000, @editor.settings.get(:timeoutlen)
  end

  def test_tm_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set tm=500'))
    assert_equal 500, @editor.settings.get(:timeoutlen)
  end

  def test_ttimeoutlen_default_minus_one
    assert_equal(-1, @editor.settings.get(:ttimeoutlen))
  end

  def test_set_ttimeoutlen
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set ttimeoutlen=50'))
    assert_equal 50, @editor.settings.get(:ttimeoutlen)
  end
end

class TestIsfnameIsident < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_isfname_default
    assert_match(/48-57/, @editor.settings.get(:isfname))
  end

  def test_isf_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set isf=a-z,A-Z,_'))
    assert_equal 'a-z,A-Z,_', @editor.settings.get(:isfname)
  end

  def test_isident_default
    assert_match(/192-255/, @editor.settings.get(:isident))
  end

  def test_isi_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set isi=a-z,A-Z'))
    assert_equal 'a-z,A-Z', @editor.settings.get(:isident)
  end
end
