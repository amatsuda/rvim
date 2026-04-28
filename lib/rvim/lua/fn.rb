# frozen_string_literal: true

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

      def has?(feat)
        case feat
        when 'nvim' then false
        when 'mac', 'macunix' then RUBY_PLATFORM.include?('darwin')
        when 'unix' then !RUBY_PLATFORM.include?('mswin')
        when 'win32', 'win64' then RUBY_PLATFORM.include?('mswin')
        when 'linux' then RUBY_PLATFORM.include?('linux')
        when 'lua' then true
        else false
        end
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

      def stdpath(what)
        cache = ENV['XDG_CACHE_HOME'] || File.expand_path('~/.cache')
        config = ENV['XDG_CONFIG_HOME'] || File.expand_path('~/.config')
        data = ENV['XDG_DATA_HOME'] || File.expand_path('~/.local/share')
        case what
        when 'config' then File.join(config, 'rvim')
        when 'data' then File.join(data, 'rvim')
        when 'cache' then File.join(cache, 'rvim')
        when 'state' then File.join(cache, 'rvim', 'state')
        when 'log' then File.join(cache, 'rvim', 'log')
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
