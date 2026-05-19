# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

module Rvim
  module Lua
    # vim.fn — shims for vim's builtin functions. v3.6 ships a curated
    # whitelist; plugins that call something not yet shimmed get a clear
    # "not implemented" error rather than silently misbehaving.
    module Fn
      module_function

      def install(state, editor, _runtime)
        state.eval('vim.fn = vim.fn or {}')

        state.function('vim.fn.expand')       { |arg| expand(editor, arg.to_s) }
        state.function('vim.fn.getcwd')       { Dir.pwd }
        state.function('vim.fn.has')          { |feat| has?(feat.to_s) ? 1 : 0 }
        state.function('vim.fn.exists')       { |name| exists?(editor, name.to_s) ? 1 : 0 }
        state.function('vim.fn.line')         { |arg| line(editor, arg.to_s) }
        state.function('vim.fn.col')          { |arg| col(editor, arg.to_s) }
        state.function('vim.fn.mode')         { mode(editor) }
        state.function('vim.fn.bufnr')        { |arg| bufnr(editor, arg.to_s) }
        state.function('vim.fn.winnr')        { (editor.windows || []).index(editor.current_window).to_i + 1 }
        state.function('vim.fn.fnamemodify')  { |path, mods| fnamemodify(path.to_s, mods.to_s) }
        state.function('vim.fn.filereadable') { |path| File.file?(File.expand_path(path.to_s)) ? 1 : 0 }
        state.function('vim.fn.isdirectory')  { |path| File.directory?(File.expand_path(path.to_s)) ? 1 : 0 }
        state.function('vim.fn.system')       { |cmd| Rvim::Filter.run(cmd.to_s).stdout }
        state.function('vim.fn.shellescape')  { |s| shellescape(s.to_s) }
        state.function('vim.fn.getenv')       { |name| ENV[name.to_s] }
        state.function('vim.fn.setenv')       { |name, val| ENV[name.to_s] = val.to_s }
        state.function('vim.fn.empty')        { |v| empty?(v) ? 1 : 0 }
        state.function('vim.fn.len')          { |v| len(v) }
        state.function('vim.fn.type')         { |v| type_id(v) }
        state.function('vim.fn.split')        { |s, sep| split_to_array(s.to_s, sep&.to_s) }
        state.function('vim.fn.join')         { |t, sep| join_lua_table(t, sep&.to_s) }
        state.function('vim.fn.substitute')   { |s, pat, rep, flags| substitute(s.to_s, pat.to_s, rep.to_s, flags.to_s) }
        state.function('vim.fn.tolower')      { |s| s.to_s.downcase }
        state.function('vim.fn.toupper')      { |s| s.to_s.upcase }
        state.function('vim.fn.trim')         { |s| s.to_s.strip }
        state.function('vim.fn.min')          { |t| values_of(t).min }
        state.function('vim.fn.max')          { |t| values_of(t).max }
        state.function('vim.fn.stdpath')      { |what| stdpath(what.to_s) }
        state.function('vim.fn.executable')   { |name| ENV['PATH'].to_s.split(':').any? { |d| File.executable?(File.join(d, name.to_s)) } ? 1 : 0 }
        state.function('vim.fn.exepath')      { |name| exepath(name.to_s) }
        state.function('vim.fn.mkdir')        { |path, flags, mode| mkdir(path.to_s, flags.to_s, mode) }
        state.function('vim.fn.delete')       { |path, flags| delete(path.to_s, flags.to_s) }
        state.function('vim.fn.glob')         { |pat, _nosuf, list, _alllinks| glob(pat.to_s, list == 1 || list == true) }
        state.function('vim.fn.globpath')     { |dirs, pat, _nosuf, list| globpath(dirs.to_s, pat.to_s, list == 1 || list == true) }
        state.function('vim.fn.tempname')     { File.join(Dir.tmpdir, "rvim_#{Process.pid}_#{rand(1 << 30).to_s(36)}") }
        state.function('vim.fn.simplify')     { |path| File.expand_path(path.to_s).gsub(%r{/+}, '/') }
        state.function('vim.fn.resolve')      { |path| File.exist?(path.to_s) ? File.realpath(path.to_s) : path.to_s }
        state.function('vim.fn.getfsize')     { |path| File.exist?(path.to_s) ? File.size(path.to_s) : -1 }
        state.function('vim.fn.getftime')     { |path| File.exist?(path.to_s) ? File.mtime(path.to_s).to_i : -1 }
        state.function('vim.fn.reltime')      { [Time.now.to_i, Time.now.usec] }
        state.function('vim.fn.reltimestr')   { |t| format_reltime(t) }
        state.function('vim.fn.reltimefloat') { |t| reltime_to_float(t) }
        state.function('vim.fn.localtime')    { Time.now.to_i }
        state.function('vim.fn.strftime')     { |fmt, time| Time.at((time || Time.now.to_i).to_i).strftime(fmt.to_s) }
        state.function('vim.fn.getcompletion'){ |pat, type, _filt| getcompletion(editor, pat.to_s, type.to_s) }
      end

      # vim.fn.getcompletion(pat, type) — return matches for the given
      # completion type. Plugins probe a small handful: "color",
      # "command", "filetype", "buffer", "function". Anything we
      # don't recognize returns []; the caller's job is to fall
      # through to the no-match path.
      def getcompletion(editor, pat, type)
        case type
        when 'color'
          rtp_glob(editor, 'colors/*.vim') + rtp_glob(editor, 'colors/*.lua')
        when 'command'
          editor.user_commands.keys.select { |n| n.start_with?(pat) }
        when 'filetype'
          rtp_glob(editor, 'ftplugin/*.vim').map { |p| File.basename(p, '.vim') }.uniq
        when 'buffer'
          (editor.buffers&.values || []).map { |b| b.filepath.to_s }.reject(&:empty?)
        when 'function'
          # We can't introspect Lua-defined functions; return [] so
          # callers fall through.
          []
        else
          []
        end
      end

      def rtp_glob(editor, pat)
        editor.settings.get(:runtimepath).to_s.split(',').flat_map do |dir|
          dir = File.expand_path(dir.strip)
          Dir.glob(File.join(dir, pat)).map { |p| File.basename(p).sub(/\.(vim|lua)\z/, '') }
        end.uniq
      end

      def mkdir(path, flags, mode)
        recursive = flags.include?('p')
        if recursive
          FileUtils.mkdir_p(path)
        elsif !File.directory?(path)
          Dir.mkdir(path)
        end
        mode_int = mode.respond_to?(:to_i) ? mode.to_i : nil
        File.chmod(mode_int, path) if mode_int && mode_int.positive?
        1
      rescue StandardError
        0
      end

      def delete(path, flags)
        recursive = flags.include?('d') || flags.include?('rf')
        if recursive && File.directory?(path)
          FileUtils.rm_rf(path)
        elsif File.exist?(path)
          File.delete(path)
        end
        0
      rescue StandardError
        -1
      end

      def glob(pat, list)
        results = Dir.glob(File.expand_path(pat))
        list ? results : results.join("\n")
      end

      def globpath(dirs, pat, list)
        results = dirs.split(',').flat_map { |d| Dir.glob(File.join(File.expand_path(d.strip), pat)) }
        list ? results : results.join("\n")
      end

      def reltime_to_float(t)
        arr = t.respond_to?(:to_h) ? t.to_h.values : Array(t)
        arr[0].to_f + arr[1].to_f / 1_000_000.0
      end

      def format_reltime(t)
        f = reltime_to_float(t)
        format('%.6f', f)
      end

      def expand(editor, arg)
        case arg
        when /\A%(:.+)?\z/
          path = editor.filepath.to_s
          mods = arg.sub(/\A%/, '')
          fnamemodify(path, mods)
        when /\A#(:.+)?\z/
          alt = editor.instance_variable_get(:@alternate_filepath).to_s
          mods = arg.sub(/\A#/, '')
          fnamemodify(alt, mods)
        when /\A<\w+>\z/ then ''
        else File.expand_path(arg)
        end
      end

      def fnamemodify(path, mods)
        result = path.to_s
        i = 0
        while i < mods.length
          c = mods[i]
          if c == ':'
            i += 1
            next
          end
          case c
          when 'p' then result = File.expand_path(result)
          when 'h' then result = File.dirname(result)
          when 't' then result = File.basename(result)
          when 'r' then result = result.sub(/\.[^.\/]+\z/, '')
          when 'e' then result = File.extname(result).sub(/\A\./, '')
          end
          i += 1
        end
        result
      end

      # The version of NeoVim we present ourselves as. Lazy.nvim and
      # many plugins gate features on has("nvim-X.Y.Z"); claiming 0.10
      # unlocks the modern plugin path (autocmds API, vim.system,
      # vim.loop→vim.uv, vim.loader) without forcing us to also
      # implement every 0.11+ surface.
      CLAIMED_NVIM_VERSION = [0, 10, 0].freeze

      def has?(feat)
        # nvim-X[.Y[.Z]] version gate.
        if (m = feat.match(/\Anvim-(\d+)(?:\.(\d+))?(?:\.(\d+))?\z/))
          asked = [m[1].to_i, m[2].to_i, m[3].to_i]
          return version_at_least?(CLAIMED_NVIM_VERSION, asked)
        end

        case feat
        when 'nvim' then true
        when 'mac', 'macunix' then RUBY_PLATFORM.include?('darwin')
        when 'unix' then !RUBY_PLATFORM.include?('mswin')
        when 'win32', 'win64' then RUBY_PLATFORM.include?('mswin')
        when 'linux' then RUBY_PLATFORM.include?('linux')
        when 'lua' then true
        # ffi exists as a stub but real cdef calls would fail; plugins
        # that *only* check presence pass, plugins that exercise C
        # bindings fall through to their fallback path.
        when 'ffi' then true
        when 'jit' then true
        when 'vim_starting' then false
        else false
        end
      end

      def version_at_least?(have, want)
        [0, 1, 2].each do |i|
          return true  if have[i] > want[i]
          return false if have[i] < want[i]
        end
        true
      end

      def exists?(editor, name)
        case name
        when /\A&(.+)\z/ then editor.settings.known?(Regexp.last_match(1))
        when /\Ag:(.+)\z/ then editor.let_vars.key?(Regexp.last_match(1))
        when /\A:(.+)\z/ then true
        else false
        end
      end

      def line(editor, arg)
        case arg
        when '.' then editor.line_index + 1
        when '$' then editor.buffer_of_lines.size
        else 0
        end
      end

      def col(editor, arg)
        case arg
        when '.' then editor.byte_pointer + 1
        when '$' then ((editor.buffer_of_lines[editor.line_index] || '').bytesize) + 1
        else 0
        end
      end

      def mode(editor)
        case editor.editing_mode_label
        when :vi_command then 'n'
        when :vi_insert then 'i'
        else editor.editing_mode_label.to_s
        end
      end

      def bufnr(editor, arg)
        case arg
        when '%' then editor.current_buffer&.id || -1
        when '#' then -1
        else
          buf = editor.buffers&.values&.find { |b| b.filepath == arg }
          buf ? buf.id : -1
        end
      end

      def shellescape(s)
        return "''" if s.empty?

        "'#{s.gsub("'", %q('\\\\''))}'"
      end

      def empty?(v)
        case v
        when nil, '', 0, 0.0 then true
        when Hash, Array then v.empty?
        else
          v.respond_to?(:to_h) ? v.to_h.empty? : false
        end
      end

      def len(v)
        case v
        when nil then 0
        when String then v.length
        when Hash, Array then v.size
        else
          v.respond_to?(:to_h) ? v.to_h.size : 0
        end
      end

      def type_id(v)
        case v
        when Numeric then 0
        when String then 1
        when nil then 7
        when TrueClass, FalseClass then 6
        else
          v.respond_to?(:to_h) ? 4 : 0
        end
      end

      def values_of(t)
        return t if t.is_a?(Array)
        return t.to_h.values if t.respond_to?(:to_h)

        Array(t)
      end

      def split_to_array(s, sep)
        s.split(sep || /\s+/)
      end

      def join_lua_table(t, sep)
        values_of(t).join(sep || ' ')
      end

      def substitute(s, pat, rep, flags)
        regex = Regexp.new(pat)
        if flags.include?('g')
          s.gsub(regex, rep)
        else
          s.sub(regex, rep)
        end
      end

      # Matches NeoVim's stdpath() with XDG fallbacks. We use 'rvim'
      # rather than 'nvim' so plugin managers like lazy.nvim cache
      # under ~/.local/share/rvim/lazy/, leaving any nvim install
      # untouched.
      def stdpath(what)
        cache  = ENV['XDG_CACHE_HOME']  || File.expand_path('~/.cache')
        config = ENV['XDG_CONFIG_HOME'] || File.expand_path('~/.config')
        data   = ENV['XDG_DATA_HOME']   || File.expand_path('~/.local/share')
        state  = ENV['XDG_STATE_HOME']  || File.expand_path('~/.local/state')
        case what
        when 'config'      then File.join(config, 'rvim')
        when 'data'        then File.join(data,   'rvim')
        when 'cache'       then File.join(cache,  'rvim')
        when 'state'       then File.join(state,  'rvim')
        when 'log'         then File.join(state,  'rvim', 'log')
        when 'run'         then File.join('/tmp', "rvim.#{Process.uid}")
        when 'config_dirs' then [File.join(config, 'rvim')]
        when 'data_dirs'   then [File.join(data, 'rvim')]
        else ''
        end
      end

      def exepath(name)
        ENV['PATH'].to_s.split(':').each do |dir|
          path = File.join(dir, name)
          return path if File.executable?(path) && !File.directory?(path)
        end
        ''
      end
    end
  end
end
