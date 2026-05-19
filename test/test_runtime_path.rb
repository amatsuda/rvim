# frozen_string_literal: true

require_relative 'test_helper'

# Rvim ships a minimal $VIMRUNTIME at `runtime/` so plugins that
# source filetype.lua at startup (lazy.nvim does this) and any code
# that consults `&runtimepath` for bundled colors/help/syntax files
# resolves to a real path.

class TestRuntimePath < Test::Unit::TestCase
  def test_runtime_path_constant_points_at_real_directory
    assert File.directory?(Rvim::RUNTIME_PATH), "expected #{Rvim::RUNTIME_PATH} to exist"
  end

  def test_runtime_ships_filetype_lua
    assert File.file?(File.join(Rvim::RUNTIME_PATH, 'filetype.lua'))
  end

  def test_runtime_ships_default_colorscheme
    assert File.file?(File.join(Rvim::RUNTIME_PATH, 'colors', 'default.vim'))
  end

  def test_runtime_ships_help_txt
    assert File.file?(File.join(Rvim::RUNTIME_PATH, 'doc', 'help.txt'))
  end

  def test_ensure_bundled_runtime_sets_vimruntime_env
    prev = ENV.delete('VIMRUNTIME')
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_bundled_runtime(editor)
    assert_equal Rvim::RUNTIME_PATH, ENV['VIMRUNTIME']
  ensure
    if prev
      ENV['VIMRUNTIME'] = prev
    else
      ENV.delete('VIMRUNTIME')
    end
  end

  def test_ensure_bundled_runtime_respects_existing_env
    prev = ENV['VIMRUNTIME']
    ENV['VIMRUNTIME'] = '/some/other/path'
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_bundled_runtime(editor)
    assert_equal '/some/other/path', ENV['VIMRUNTIME']
  ensure
    if prev
      ENV['VIMRUNTIME'] = prev
    else
      ENV.delete('VIMRUNTIME')
    end
  end

  def test_ensure_bundled_runtime_prepends_to_runtimepath
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_bundled_runtime(editor)
    rtp = editor.settings.get(:runtimepath).to_s.split(',')
    assert_equal Rvim::RUNTIME_PATH, rtp.first
  end

  def test_ensure_bundled_runtime_is_idempotent
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_bundled_runtime(editor)
    Rvim::Editor.ensure_bundled_runtime(editor)
    count = editor.settings.get(:runtimepath).to_s.split(',').count(Rvim::RUNTIME_PATH)
    assert_equal 1, count
  end

  def test_nvim_get_runtime_file_finds_bundled_filetype_lua
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?

    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_bundled_runtime(editor)
    result = editor.lua.eval(<<~LUA)
      local r = vim.api.nvim_get_runtime_file("filetype.lua", false)
      return r[1]
    LUA
    assert_equal File.join(Rvim::RUNTIME_PATH, 'filetype.lua'), result
  end

  def test_vim_env_vimruntime_visible_from_lua
    omit 'Lua not available on this system' unless Rvim::Lua::Runtime.available?

    prev = ENV.delete('VIMRUNTIME')
    editor = Rvim::Editor.new(Reline.core.config)
    Rvim::Editor.ensure_bundled_runtime(editor)
    assert_equal Rvim::RUNTIME_PATH, editor.lua.eval('return vim.env.VIMRUNTIME')
  ensure
    if prev
      ENV['VIMRUNTIME'] = prev
    else
      ENV.delete('VIMRUNTIME')
    end
  end
end
