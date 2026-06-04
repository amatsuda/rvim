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

        state.function('vim.fn.expand')       { |arg, _nosuf, list| expand(editor, arg.to_s, as_list: list == 1 || list == true) }
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
        state.function('vim.fn.system')       { |cmd, input| run_system(editor, cmd, input) }
        state.function('vim.fn.systemlist')   { |cmd, input| run_system(editor, cmd, input).split("\n") }
        state.function('vim.fn.shellescape')  { |s| shellescape(s.to_s) }
        # fnameescape({string}) — escape Vim filename-special chars
        # so the result is safe to splice into an ex command argument.
        # Telescope's actions.edit uses this to build the
        # `:edit /path/with spaces.rb` line that opens the picked
        # entry; without the shim, calling it errors before pcall
        # captures the surrounding vim.cmd, the keymap callback
        # swallows the LuaError, and the file silently never opens.
        state.function('vim.fn.fnameescape')  { |s| fnameescape(s.to_s) }
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
        # Window-type probes used by telescope to detect "are we in a
        # quickfix/preview?". rvim only has normal and floating windows;
        # return "" for both (NeoVim semantics for normal windows).
        state.function('vim.fn.win_gettype') { |_winid| '' }
        # Prompt-buffer ("buftype=prompt") helpers — used by telescope's
        # input line. In NeoVim a prompt buffer renders the prefix as
        # part of line 0 (the buffer text literally starts with the
        # prefix); telescope's _get_prompt() reads the line and strips
        # `#prompt_prefix` bytes off the front to recover what the
        # user typed. Our editor doesn't model "prompt buffer" type
        # semantics, so prepend the prefix into the buffer text up
        # front and remember it so we can swap it on later calls.
        state.function('vim.fn.prompt_setprompt') do |bufnr, str|
          buf = Rvim::Lua::Api.resolve_buffer(editor, bufnr)
          if buf
            new_prefix = str.to_s
            old_prefix = (buf.vars['_rvim_prompt_prefix'] || '').to_s
            line0 = (buf.lines[0] || '').to_s
            # Strip any previously-set prefix from the head of line 0
            # before installing the new one — change_prompt_prefix
            # may call this with a different prefix mid-session.
            if !old_prefix.empty? && line0.start_with?(old_prefix)
              line0 = line0[old_prefix.length..]
            end
            buf.lines[0] = String.new(new_prefix + line0, encoding: editor.encoding)
            buf.vars['_rvim_prompt_prefix'] = new_prefix
            # In NeoVim a prompt buffer parks the cursor at the end of
            # the prompt — `i` then inserts after the prefix. Without
            # this, our editor sits at col 0 and the user's first
            # keystroke lands *before* the prefix, so _get_prompt
            # strips the user's typing instead of the prefix.
            buf.byte_pointer = new_prefix.bytesize
            buf.line_index = 0
            if buf == editor.current_buffer
              editor.instance_variable_set(:@buffer_of_lines, buf.lines)
              editor.instance_variable_set(:@byte_pointer, buf.byte_pointer)
              editor.instance_variable_set(:@line_index, 0)
            end
          end
          0
        end
        state.function('vim.fn.prompt_setcallback') { |_bufnr, _cb|  0 }
        state.function('vim.fn.prompt_setinterrupt'){ |_bufnr, _cb|  0 }
        state.function('vim.fn.prompt_getprompt') do |bufnr|
          buf = Rvim::Lua::Api.resolve_buffer(editor, bufnr)
          (buf && buf.vars['_rvim_prompt_prefix']) || ''
        end
        state.function('vim.fn.win_getid')   { |_winnr, _tabnr| editor.current_window&.id || 0 }
        state.function('vim.fn.win_id2win')  { |_winid| 1 }
        state.function('vim.fn.winnr')       { |_arg| (editor.windows || []).index(editor.current_window).to_i + 1 }
        state.function('vim.fn.winwidth')    { |_winid|
          (Reline::IOGate.get_screen_size[1] rescue 80)
        }
        state.function('vim.fn.winheight')   { |_winid|
          (Reline::IOGate.get_screen_size[0] rescue 24)
        }

        # Character / byte utilities. keytrans is normally the inverse
        # of nvim_replace_termcodes — translates internal byte
        # sequences (\x80\xfd<...>) to readable <Key> forms. For plain
        # ASCII strings (rvim's usual case) it's identity; complex
        # encodings are out of scope here.
        state.function('vim.fn.keytrans')   { |s| s.to_s }
        state.function('vim.fn.str2list')   { |s, _utf8| s.to_s.bytes }
        state.function('vim.fn.nr2char')    { |n, _utf8| n.to_i < 0x80 ? n.to_i.chr : [n.to_i].pack('U') }
        state.function('vim.fn.char2nr')    { |s, _utf8| s.to_s.empty? ? 0 : s.to_s.codepoints.first }
        state.function('vim.fn.reg_recording') { editor.instance_variable_get(:@recording_macro).to_s }
        state.function('vim.fn.reg_executing') { '' }
        state.function('vim.fn.strchars')   { |s, _skip| s.to_s.length }
        state.function('vim.fn.strdisplaywidth') { |s, _col| s.to_s.length }
        # Popup-menu visibility probe. Telescope's <Esc> action checks
        # pumvisible() before closing the picker; without the shim
        # Reline-side completion popups aren't a concept telescope
        # cares about anyway, so always return 0 (no menu visible).
        state.function('vim.fn.pumvisible')      { 0 }
        # strcharpart({src}, {start} [, {len} [, {skipcc}]]) — substring
        # by character index/length (not byte). plenary.strings uses it
        # as a fallback when its FFI utf_ptr2len path is unavailable.
        state.function('vim.fn.strcharpart') do |s, start, len, _skipcc|
          chars = s.to_s.chars
          st = start.to_i
          if st < 0
            # Vim clamps negative start to 0 but shortens len by the deficit.
            len = len.to_i + st if len
            st = 0
          end
          if len.nil?
            chars[st..].to_a.join
          else
            chars[st, [len.to_i, 0].max].to_a.join
          end
        end
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

      # vim.fn.system(cmd[, input])
      #   cmd can be a string (run via shell) OR a list (argv form, no
      #   shell). NeoVim distinguishes: lazy.nvim's bootstrap uses the
      #   list form to git-clone safely. We mirror that and set
      #   v:shell_error to the exit status.
      def run_system(editor, cmd, input)
        argv = lua_to_argv(cmd)
        in_str = input.respond_to?(:to_s) ? input.to_s : ''
        out, err, status = if argv.is_a?(Array)
                             require 'open3'
                             Open3.capture3(*argv, stdin_data: in_str)
                           else
                             require 'open3'
                             Open3.capture3('/bin/sh', '-c', argv.to_s, stdin_data: in_str)
                           end
        v = editor.instance_variable_get(:@lua_v_vars)
        v['shell_error'] = status.exitstatus if v
        out + err
      rescue StandardError => e
        v = editor.instance_variable_get(:@lua_v_vars)
        v['shell_error'] = 1 if v
        e.message.to_s
      end

      def lua_to_argv(cmd)
        if cmd.respond_to?(:to_h)
          # rufus-lua hands back Lua tables with Float keys (1.0, 2.0).
          h = cmd.to_h
          return '' if h.empty?

          (1..h.size).map { |i| (h[i] || h[i.to_f]).to_s }
        elsif cmd.is_a?(Array)
          cmd
        else
          cmd.to_s
        end
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

      def expand(editor, arg, as_list: false)
        result = case arg
                 when /\A%(:.+)?\z/
                   path = editor.filepath.to_s
                   mods = arg.sub(/\A%/, '')
                   fnamemodify(path, mods)
                 when /\A#(:.+)?\z/
                   alt = editor.instance_variable_get(:@alternate_filepath).to_s
                   mods = arg.sub(/\A#/, '')
                   fnamemodify(alt, mods)
                 when /\A<\w+>\z/ then ''
                 else
                   path = File.expand_path(arg)
                   # When the path contains a glob, expand to matches.
                   # In list mode we always return an array (possibly empty);
                   # in string mode vim returns matches joined by \n, or the
                   # original pattern if nothing matched.
                   if path.match?(/[\*\?\[]/) || arg.include?('**')
                     matches = Dir.glob(path)
                     return matches if as_list

                     matches.empty? ? path : matches.join("\n")
                   else
                     path
                   end
                 end
        as_list ? [result.to_s] : result
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
      CLAIMED_NVIM_VERSION = [0, 11, 0].freeze

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

      # Vim's fnameescape: backslash-escape characters that the ex
      # command-line parser treats as special when reading a filename.
      # Order matters — '\\' has to be first so we don't double-escape
      # the backslashes we just introduced.
      FNAMESCAPE_CHARS = ['\\', ' ', "\t", "\n", '*', '?', '[', '{', '`',
                          '$', '%', '#', "'", '"', '|', '!', '<'].freeze
      def fnameescape(s)
        out = s.dup
        FNAMESCAPE_CHARS.each { |c| out.gsub!(c, '\\' + c) }
        out
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
