# frozen_string_literal: true

require_relative 'test_helper'

class TestPrintheaderStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_default
    assert_match(/Page/, @editor.settings.get(:printheader))
  end

  def test_pheader_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pheader=%f'))
    assert_equal '%f', @editor.settings.get(:printheader)
  end
end

class TestPrintoptionsStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:printoptions)
  end

  def test_popt_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set popt=duplex:long'))
    assert_equal 'duplex:long', @editor.settings.get(:printoptions)
  end
end

class TestPrintfontStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_courier
    assert_equal 'courier', @editor.settings.get(:printfont)
  end

  def test_pfn_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pfn=monaco:h10'))
    assert_equal 'monaco:h10', @editor.settings.get(:printfont)
  end
end

class TestPrintencodingStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:printencoding)
  end

  def test_penc_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set penc=utf-8'))
    assert_equal 'utf-8', @editor.settings.get(:printencoding)
  end
end

class TestPrintexprStorage < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def test_default_empty
    assert_equal '', @editor.settings.get(:printexpr)
  end

  def test_pexpr_alias
    Rvim::Command.execute(@editor, Rvim::Command.parse(':set pexpr=system(...)'))
    assert_equal 'system(...)', @editor.settings.get(:printexpr)
  end
end
