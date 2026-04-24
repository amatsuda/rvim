# frozen_string_literal: true

module Rvim
  class Command
    Parsed = Struct.new(:verb, :arg, :bang, :line_number, :sub, :range, :set_options, keyword_init: true)

    SET_TOKEN_RE = /\A(no)?(\w+)(?:=(\S+))?\??\z/

    SUBSTITUTE_RE = %r{
      \A
      (?<range>%|\d+(?:,\d+)?|'<,'>)?
      s/
      (?<pat>(?:\\.|[^/])*)
      /
      (?<rep>(?:\\.|[^/])*)
      /?
      (?<flags>[gi]*)?
      \z
    }x

    FILTER_RE = /\A(?<range>%|\d+(?:,\d+)?|'<,'>)?!(?<cmd>.*)\z/.freeze

    SORT_RE = /\A
      (?<range>%|\d+(?:,\d+)?|'<,'>)?
      \s*sort
      (?<bang>!)?
      (?:\s+(?<flags>[uni]+))?
      \z
    /x.freeze

    def self.parse(input)
      str = input.to_s.dup
      str = str[1..] if str.start_with?(':')
      str.strip!
      return nil if str.empty?

      if (m = SUBSTITUTE_RE.match(str))
        return Parsed.new(
          verb: :sub,
          range: parse_range(m[:range]),
          sub: {
            pattern: m[:pat],
            replacement: m[:rep],
            global: m[:flags].to_s.include?('g'),
            ignorecase: m[:flags].to_s.include?('i'),
          },
          arg: nil,
          bang: false,
          line_number: nil,
        )
      end

      if (m = FILTER_RE.match(str))
        if m[:range]
          return Parsed.new(verb: :filter, range: parse_range(m[:range]), arg: m[:cmd], bang: false, line_number: nil)
        else
          return Parsed.new(verb: :bang, arg: m[:cmd], bang: false, line_number: nil)
        end
      end

      if (m = SORT_RE.match(str))
        return Parsed.new(
          verb: :sort,
          range: m[:range] ? parse_range(m[:range]) : nil,
          arg: m[:flags].to_s,
          bang: !m[:bang].nil?,
          line_number: nil,
        )
      end

      if str.match?(/\A\d+\z/)
        return Parsed.new(verb: :goto, arg: nil, bang: false, line_number: str.to_i)
      end

      # Generic range prefix: strip a leading range like 5,10 or % or '<,'>
      # if it's followed by an alphabetic verb. Substitute/filter/sort have
      # their own range parsing above, so they never reach this path.
      generic_range = nil
      if (m = /\A(?<r>%|\d+(?:,\d+)?|'<,'>)\s*(?<rest>[a-zA-Z].*)\z/.match(str))
        generic_range = parse_range(m[:r])
        str = m[:rest]
      end

      tokens = str.split(/\s+/, 2)
      head = tokens[0]
      arg = tokens[1]
      # Allow short verbs with an immediate numeric argument (e.g. :1t2, :5d3).
      # Split the leading letters off the head when the rest is digits.
      if (m = /\A(?<verb>[a-zA-Z]+!?)(?<rest>\d.*)\z/.match(head))
        head = m[:verb]
        arg = arg ? "#{m[:rest]} #{arg}" : m[:rest]
      end
      bang = head.end_with?('!')
      verb_str = bang ? head.chomp('!') : head

      verb = case verb_str
             when 'w', 'write' then :w
             when 'q', 'quit' then :q
             when 'qa', 'qall', 'quitall' then :qa
             when 'wq' then :wq
             when 'x' then :wq
             when 'cq', 'cquit' then :cq
             when 'e', 'edit' then :e
             when 'r', 'read' then :r
             when 'bn', 'bnext' then :bn
             when 'bp', 'bprev', 'bprevious' then :bp
             when 'b', 'buffer' then :b
             when 'bd', 'bdelete' then :bd
             when 'sp', 'split' then :sp
             when 'vsp', 'vsplit' then :vsp
             when 'set', 'se' then :set
             when 'setlocal', 'setl' then :setlocal
             when 'ls', 'buffers', 'files' then :ls
             when 'marks' then :marks
             when 'jumps' then :jumps
             when 'registers', 'reg', 'display' then :registers
             when 'tabnext', 'tabn' then :tabnext
             when 'tabprev', 'tabp', 'tabprevious', 'tabNext' then :tabprev
             when 'tabnew', 'tabe', 'tabedit' then :tabnew
             when 'tabclose', 'tabc' then :tabclose
             when 'tabonly', 'tabo' then :tabonly
             when 'tabmove', 'tabm' then :tabmove
             when 'resize', 'res' then :resize
             when 'vertical' then :vertical
             when 'source', 'so' then :source
             when 'runtime', 'runt' then :runtime
             when 'packadd' then :packadd
             when 'history', 'his' then :history
             when 'map' then :map
             when 'nmap' then :nmap
             when 'vmap' then :vmap
             when 'imap' then :imap
             when 'omap' then :omap
             when 'noremap', 'no' then :noremap
             when 'nnoremap', 'nn' then :nnoremap
             when 'vnoremap', 'vn' then :vnoremap
             when 'inoremap', 'ino' then :inoremap
             when 'onoremap', 'ono' then :onoremap
             when 'unmap', 'unm' then :unmap
             when 'nunmap', 'nun' then :nunmap
             when 'vunmap', 'vu' then :vunmap
             when 'iunmap', 'iu' then :iunmap
             when 'ounmap', 'ou' then :ounmap
             when 'mapclear', 'mapc' then :mapclear
             when 'nmapclear', 'nmapc' then :nmapclear
             when 'vmapclear', 'vmapc' then :vmapclear
             when 'imapclear', 'imapc' then :imapclear
             when 'omapclear', 'omapc' then :omapclear
             when 'cmap', 'cm' then :cmap
             when 'cnoremap', 'cno' then :cnoremap
             when 'cunmap', 'cun' then :cunmap
             when 'cmapclear', 'cmapc' then :cmapclear
             when 'abbreviate', 'abbrev', 'ab' then :abbrev
             when 'iabbrev', 'iab' then :iabbrev
             when 'cabbrev', 'ca' then :cabbrev
             when 'noreabbrev', 'norea' then :noreabbrev
             when 'inoreabbrev', 'inoreab' then :inoreabbrev
             when 'cnoreabbrev', 'cnorea' then :cnoreabbrev
             when 'unabbreviate', 'una' then :unabbrev
             when 'iunabbrev', 'iuna' then :iunabbrev
             when 'cunabbrev', 'cuna' then :cunabbrev
             when 'abclear', 'abc' then :abclear
             when 'iabclear', 'iabc' then :iabclear
             when 'cabclear', 'cabc' then :cabclear
             when 'let' then :let
             when 'fold', 'fo' then :fold
             when 'autocmd', 'au' then :autocmd
             when 'augroup', 'aug' then :augroup
             when 'd', 'delete' then :delete
             when 'y', 'yank' then :yank
             when 'p', 'put' then :put
             when 'm', 'move' then :move
             when 'co', 'copy', 't' then :copy
             when 'j', 'join' then :join
             when 'noh', 'nohlsearch' then :nohlsearch
             when 'retab' then :retab
             when 'cd', 'chdir' then :cd
             when 'pwd' then :pwd
             when 'vimgrep', 'vim' then :vimgrep
             when 'cnext', 'cn' then :cnext
             when 'cprev', 'cp', 'cprevious' then :cprev
             when 'cc' then :cc
             when 'clist', 'cl' then :clist
             when 'copen', 'cope' then :copen
             when 'cclose', 'cclo' then :cclose
             when 'lvimgrep', 'lvim' then :lvimgrep
             when 'lnext', 'lne' then :lnext
             when 'lprev', 'lp', 'lprevious' then :lprev
             when 'll' then :ll
             when 'llist', 'll!' then :llist
             when 'lopen', 'lop' then :lopen
             when 'lclose', 'lcl' then :lclose
             when 'lmake' then :lmake
             when 'lgrep' then :lgrep
             when 'diffthis', 'difft' then :diffthis
             when 'diffoff' then :diffoff
             when 'diffupdate', 'diffu' then :diffupdate
             when 'diffsplit', 'diffs' then :diffsplit
             when 'hi', 'highlight' then :hi
             when 'colorscheme', 'colo' then :colorscheme
             when 'digraph', 'digraphs', 'dig' then :digraphs
             when 'tag', 'ta' then :tag
             when 'tags' then :tags_list
             when 'tnext', 'tn' then :tnext
             when 'tprev', 'tp', 'tprevious' then :tprev
             when 'bufdo' then :bufdo
             when 'tabdo' then :tabdo
             when 'windo' then :windo
             when 'argdo' then :argdo
             when 'args', 'ar' then :args
             when 'argadd', 'arga' then :argadd
             when 'make' then :make
             when 'grep' then :grep
             else verb_str.to_sym
             end

      if verb == :set || verb == :setlocal
        set_options = parse_set(arg)
        return Parsed.new(verb: verb, arg: arg, bang: bang, line_number: nil, set_options: set_options)
      end

      Parsed.new(verb: verb, arg: arg, bang: bang, line_number: nil, range: generic_range)
    end

    def self.parse_set(args)
      args.to_s.split(/\s+/).map do |tok|
        m = tok.match(SET_TOKEN_RE)
        next unless m

        name = m[2]
        if m[1] == 'no'
          [name, false]
        elsif m[3]
          val = m[3].match?(/\A\d+\z/) ? m[3].to_i : m[3]
          [name, val]
        else
          [name, true]
        end
      end.compact
    end

    def self.parse_range(token)
      return :current if token.nil? || token.empty?
      return :whole if token == '%'
      return :visual if token == "'<,'>"

      if token.include?(',')
        a, b = token.split(',').map(&:to_i)
        [a, b]
      else
        [token.to_i, token.to_i]
      end
    end

    def self.execute(editor, parsed)
      return unless parsed

      case parsed.verb
      when :w
        execute_write(editor, parsed)
      when :q
        execute_quit(editor, parsed)
      when :qa
        execute_quit_all(editor, parsed)
      when :wq
        execute_write(editor, parsed)
        execute_quit(editor, parsed)
      when :cq
        editor.quit!(exit_code: 1)
      when :e
        if parsed.arg.nil? || parsed.arg.empty?
          editor.status_message = 'E32: No file name'
        else
          editor.open(parsed.arg)
        end
      when :bn
        editor.next_buffer
      when :bp
        editor.prev_buffer
      when :b
        if parsed.arg.nil? || parsed.arg.empty?
          editor.status_message = 'E32: No buffer specified'
        else
          editor.switch_buffer_by(parsed.arg)
        end
      when :bd
        editor.delete_current_buffer(force: parsed.bang)
      when :set
        execute_set(editor, parsed, local: false)
      when :setlocal
        execute_set(editor, parsed, local: true)
      when :ls
        editor.show_list(format_buffers(editor))
      when :marks
        editor.show_list(format_marks(editor))
      when :jumps
        editor.show_list(format_jumps(editor))
      when :registers
        filter_chars = parsed.arg.to_s.scan(/\S/).reject { |c| c == '"' }
        editor.show_list(format_registers(editor, filter: filter_chars))
      when :tabnext
        editor.tab_advance
      when :tabprev
        editor.tab_retreat
      when :tabnew
        editor.tab_new(parsed.arg)
      when :tabclose
        editor.tab_close
      when :tabonly
        editor.tab_only
      when :tabmove
        execute_tabmove(editor, parsed)
      when :resize
        execute_resize(editor, parsed, vertical: false)
      when :vertical
        # :vertical resize N — parsed.arg should start with "resize"
        if parsed.arg.to_s.strip.start_with?('resize', 'res')
          inner = parsed.arg.to_s.sub(/\A(resize|res)\s*/, '')
          execute_resize(editor, Parsed.new(verb: :resize, arg: inner, bang: false, line_number: nil), vertical: true)
        end
      when :sp
        if parsed.arg && !parsed.arg.empty?
          editor.open(parsed.arg)
        end
        editor.split_horizontal
      when :vsp
        if parsed.arg && !parsed.arg.empty?
          editor.open(parsed.arg)
        end
        editor.split_vertical
      when :goto
        last = editor.buffer_of_lines.size - 1
        target = (parsed.line_number - 1).clamp(0, last)
        editor.push_jump
        editor.instance_variable_set(:@line_index, target)
        editor.send(:snap_to_visible)
        editor.instance_variable_set(:@byte_pointer, 0)
      when :sub
        execute_substitute(editor, parsed)
      when :source
        if parsed.arg.nil? || parsed.arg.empty?
          editor.status_message = 'E471: Argument required'
        else
          editor.source(parsed.arg)
        end
      when :runtime
        execute_runtime(editor, parsed)
      when :packadd
        execute_packadd(editor, parsed)
      when :history
        editor.show_list(format_history(editor))
      when :map, :nmap, :vmap, :imap, :omap, :cmap,
           :noremap, :nnoremap, :vnoremap, :inoremap, :onoremap, :cnoremap
        execute_map(editor, parsed)
      when :unmap, :nunmap, :vunmap, :iunmap, :ounmap, :cunmap
        execute_unmap(editor, parsed)
      when :mapclear, :nmapclear, :vmapclear, :imapclear, :omapclear, :cmapclear
        execute_mapclear(editor, parsed)
      when :abbrev, :iabbrev, :cabbrev, :noreabbrev, :inoreabbrev, :cnoreabbrev
        execute_abbrev(editor, parsed)
      when :unabbrev, :iunabbrev, :cunabbrev
        execute_unabbrev(editor, parsed)
      when :abclear, :iabclear, :cabclear
        execute_abclear(editor, parsed)
      when :let
        execute_let(editor, parsed)
      when :fold
        execute_fold(editor, parsed)
      when :bang
        execute_bang(editor, parsed)
      when :filter
        execute_filter(editor, parsed)
      when :r
        execute_read(editor, parsed)
      when :autocmd
        execute_autocmd(editor, parsed)
      when :augroup
        execute_augroup(editor, parsed)
      when :sort
        execute_sort(editor, parsed)
      when :delete
        execute_delete(editor, parsed)
      when :yank
        execute_yank(editor, parsed)
      when :put
        execute_put(editor, parsed)
      when :move
        execute_move(editor, parsed)
      when :copy
        execute_copy(editor, parsed)
      when :join
        execute_join(editor, parsed)
      when :nohlsearch
        execute_nohlsearch(editor, parsed)
      when :retab
        execute_retab(editor, parsed)
      when :cd
        execute_cd(editor, parsed)
      when :pwd
        execute_pwd(editor, parsed)
      when :vimgrep
        execute_vimgrep(editor, parsed)
      when :cnext
        execute_cnext(editor, parsed)
      when :cprev
        execute_cprev(editor, parsed)
      when :cc
        execute_cc(editor, parsed)
      when :clist, :copen
        editor.show_list(format_quickfix(editor))
      when :cclose
        editor.dismiss_list
      when :lvimgrep
        execute_lvimgrep(editor, parsed)
      when :lnext
        execute_lnext(editor, parsed)
      when :lprev
        execute_lprev(editor, parsed)
      when :ll
        execute_ll(editor, parsed)
      when :llist, :lopen
        editor.show_list(format_location_list(editor))
      when :lclose
        editor.dismiss_list
      when :lmake
        execute_lmake(editor, parsed)
      when :lgrep
        execute_lgrep(editor, parsed)
      when :diffthis
        execute_diffthis(editor, parsed)
      when :diffoff
        execute_diffoff(editor, parsed)
      when :diffupdate
        editor.recompute_diff_status
      when :diffsplit
        execute_diffsplit(editor, parsed)
      when :hi
        execute_hi(editor, parsed)
      when :colorscheme
        execute_colorscheme(editor, parsed)
      when :digraphs
        execute_digraphs(editor, parsed)
      when :tag
        execute_tag(editor, parsed)
      when :tags_list
        editor.show_list(format_tag_stack(editor))
      when :tnext
        editor.tag_next
      when :tprev
        editor.tag_prev
      when :bufdo
        execute_bufdo(editor, parsed)
      when :tabdo
        execute_tabdo(editor, parsed)
      when :windo
        execute_windo(editor, parsed)
      when :argdo
        execute_argdo(editor, parsed)
      when :args
        execute_args(editor, parsed)
      when :argadd
        execute_argadd(editor, parsed)
      when :make
        execute_make(editor, parsed)
      when :grep
        execute_grep(editor, parsed)
      else
        editor.status_message = "E492: Not an editor command: #{parsed.verb}"
      end
    end

    MAP_MODIFIER_RE = /\A<(silent|unique|buffer|expr|nowait|script)>\s+/i.freeze

    def self.execute_map(editor, parsed)
      arg = parsed.arg.to_s.strip
      modes = Rvim::Keymap.modes_for(parsed.verb, bang: parsed.bang)

      if arg.empty?
        editor.show_list(format_mappings(editor, modes))
        return
      end

      silent = false
      while (m = MAP_MODIFIER_RE.match(arg))
        silent = true if m[1].downcase == 'silent'
        arg = arg[m[0].length..-1]
      end

      lhs_raw, rhs_raw = arg.split(/\s+/, 2)
      if rhs_raw.nil? || rhs_raw.empty?
        lhs = Rvim::Keymap.expand(lhs_raw, leader: editor.mapleader)
        editor.show_list(format_mappings(editor, modes, lhs_filter: lhs))
        return
      end

      lhs = Rvim::Keymap.expand(lhs_raw, leader: editor.mapleader)
      rhs = Rvim::Keymap.expand(rhs_raw, leader: editor.mapleader)
      recursive = !Rvim::Keymap.noremap?(parsed.verb)
      editor.keymap.add(modes, lhs, rhs, recursive: recursive, silent: silent)
    end

    def self.execute_unmap(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.status_message = 'E474: Invalid argument: usage: :unmap lhs'
        return
      end

      lhs = Rvim::Keymap.expand(arg, leader: editor.mapleader)
      modes = Rvim::Keymap.modes_for(parsed.verb, bang: parsed.bang)
      editor.keymap.remove(modes, lhs)
    end

    MODE_TAGS = {
      normal: 'n',
      visual: 'v',
      insert: 'i',
      op_pending: 'o',
      cmdline: 'c',
    }.freeze

    def self.format_mappings(editor, modes, lhs_filter: nil)
      header = '   mode  lhs                rhs'
      rows = []
      modes.each do |mode|
        editor.keymap.each(mode) do |lhs, mapping|
          next if lhs_filter && lhs != lhs_filter

          tag = MODE_TAGS[mode] || ' '
          marker = mapping.recursive ? ' ' : '*'
          rows << format(
            '   %s%s    %-18s %s',
            tag,
            marker,
            Rvim::Keymap.render(lhs),
            Rvim::Keymap.render(mapping.rhs),
          )
        end
      end
      ['Mappings', header, *rows]
    end

    def self.execute_delete(editor, parsed)
      start_line, end_line = resolve_range_default_current(editor, parsed)
      register = parsed.arg.to_s.strip
      lines = editor.buffer_of_lines[start_line..end_line]
      text = lines.map(&:to_s).join("\n")
      kind = :line
      if register.empty?
        editor.send(:write_register, text, kind, register: nil)
      else
        editor.send(:write_register, text, kind, register: register)
      end
      editor.replace_line_range(start_line, end_line, [])
      ensure_buffer_nonempty(editor)
    end

    def self.execute_yank(editor, parsed)
      start_line, end_line = resolve_range_default_current(editor, parsed)
      register = parsed.arg.to_s.strip
      lines = editor.buffer_of_lines[start_line..end_line]
      text = lines.map(&:to_s).join("\n")
      kind = :line
      if register.empty?
        editor.send(:write_register, text, kind, register: nil)
      else
        editor.send(:write_register, text, kind, register: register)
      end
    end

    def self.execute_put(editor, parsed)
      register = parsed.arg.to_s.strip
      register = nil if register.empty?
      entry = editor.read_register(register)
      return unless entry

      lines = entry.text.to_s.split("\n", -1)
      lines.pop if lines.last == ''

      target = if parsed.range
                 _, end_line = resolve_sub_range(editor, parsed.range)
                 end_line
               else
                 editor.line_index
               end
      target = -1 if parsed.bang # ":put!" puts above current/range start
      if parsed.bang && parsed.range
        start_line, _ = resolve_sub_range(editor, parsed.range)
        target = start_line - 1
      end

      editor.insert_lines_after(target, lines)
    end

    def self.execute_move(editor, parsed)
      start_line, end_line = resolve_range_default_current(editor, parsed)
      target = parsed.arg.to_i
      last = editor.buffer_of_lines.size - 1
      target = target.clamp(0, last + 1)

      moving = editor.buffer_of_lines[start_line..end_line].map(&:dup)
      # Remove from original position
      editor.buffer_of_lines.slice!(start_line, end_line - start_line + 1)
      # Adjust target if it was AFTER the cut
      target -= (end_line - start_line + 1) if target > end_line
      target = target.clamp(0, editor.buffer_of_lines.size)
      editor.buffer_of_lines.insert(target, *moving)
      editor.instance_variable_set(:@line_index, target.clamp(0, [editor.buffer_of_lines.size - 1, 0].max))
      editor.instance_variable_set(:@byte_pointer, 0)
      editor.modified = true
    end

    def self.execute_copy(editor, parsed)
      start_line, end_line = resolve_range_default_current(editor, parsed)
      target = parsed.arg.to_i
      last = editor.buffer_of_lines.size - 1
      target = target.clamp(0, last + 1)

      copied = editor.buffer_of_lines[start_line..end_line].map(&:dup)
      editor.buffer_of_lines.insert(target, *copied)
      editor.instance_variable_set(:@line_index, target)
      editor.instance_variable_set(:@byte_pointer, 0)
      editor.modified = true
    end

    def self.execute_join(editor, parsed)
      start_line, end_line = if parsed.range
                               resolve_sub_range(editor, parsed.range)
                             else
                               cur = editor.line_index
                               last = [cur + 1, editor.buffer_of_lines.size - 1].min
                               [cur, last]
                             end
      return if start_line >= end_line

      sep = parsed.bang ? '' : ' '
      lines = editor.buffer_of_lines[start_line..end_line]
      first = lines.first.to_s
      rest = lines[1..-1].map { |l| l.to_s.lstrip }
      joined = parsed.bang ? (first + rest.join) : ([first.rstrip, *rest.reject(&:empty?)].join(sep))
      editor.replace_line_range(start_line, end_line, [joined])
    end

    def self.execute_nohlsearch(editor, _parsed)
      editor.instance_variable_set(:@search_matches, [])
      editor.instance_variable_set(:@search_pattern, nil)
    end

    def self.execute_retab(editor, parsed)
      width = parsed.arg.to_s.strip
      n = width.empty? ? editor.settings.get(:shiftwidth) : width.to_i
      n = 1 if n.nil? || n <= 0
      spaces = ' ' * n
      editor.buffer_of_lines.each_with_index do |line, i|
        editor.buffer_of_lines[i] = line.gsub("\t", spaces)
      end
      editor.modified = true
    end

    def self.execute_cd(editor, parsed)
      path = parsed.arg.to_s.strip
      target = path.empty? ? Dir.home : File.expand_path(path)
      Dir.chdir(target)
      editor.status_message = Dir.pwd
    rescue => e
      editor.status_message = "E: cd: #{e.message}"
    end

    def self.execute_pwd(editor, _parsed)
      editor.status_message = Dir.pwd
    end

    def self.resolve_range_default_current(editor, parsed)
      if parsed.range
        resolve_sub_range(editor, parsed.range)
      else
        # No range — ":delete N" treats arg as a count when arg looks like a number.
        count = parsed.arg.to_s.strip
        if count =~ /\A\d+\z/
          start_line = editor.line_index
          end_line = [start_line + count.to_i - 1, editor.buffer_of_lines.size - 1].min
          [start_line, end_line]
        else
          [editor.line_index, editor.line_index]
        end
      end
    end

    def self.ensure_buffer_nonempty(editor)
      if editor.buffer_of_lines.empty?
        editor.buffer_of_lines << String.new('', encoding: editor.encoding)
        editor.instance_variable_set(:@line_index, 0)
        editor.instance_variable_set(:@byte_pointer, 0)
      end
    end

    # Replace standalone % with current filepath and # with alternate.
    # Use \% / \# to escape.
    def self.expand_filenames(editor, str)
      out = +''
      i = 0
      bytes = str.to_s
      while i < bytes.length
        c = bytes[i]
        if c == '\\' && (bytes[i + 1] == '%' || bytes[i + 1] == '#')
          out << bytes[i + 1]
          i += 2
        elsif c == '%' && editor.filepath
          out << editor.filepath
          i += 1
        elsif c == '#' && editor.alternate_filepath
          out << editor.alternate_filepath
          i += 1
        else
          out << c
          i += 1
        end
      end
      out
    end

    def self.execute_make(editor, parsed)
      args = parsed.arg.to_s
      prg = editor.settings.get(:makeprg).to_s
      prg = 'make' if prg.empty?
      cmd = args.empty? ? prg : "#{prg} #{args}"
      result = Rvim::Filter.run(cmd, shell: editor.settings.get(:shell), shellcmdflag: editor.settings.get(:shellcmdflag))
      output = result.stdout.to_s + result.stderr.to_s
      entries = Rvim::Errorformat.parse(output, editor.settings.get(:errorformat))
      editor.quickfix.set(entries)
      if entries.empty?
        editor.status_message = '(No errors)'
      else
        editor.status_message = "(1 of #{entries.size}) #{format_quickfix_summary(entries.first)}"
        jump_to_quickfix_entry(editor, entries.first) unless parsed.bang
      end
    end

    def self.execute_grep(editor, parsed)
      args = parsed.arg.to_s.strip
      if args.empty?
        editor.status_message = 'E471: usage: :grep PATTERN [FILES]'
        return
      end

      prg = editor.settings.get(:grepprg).to_s
      prg = 'grep -n' if prg.empty?
      cmd = if prg.include?('$*')
              prg.sub('$*', args)
            else
              "#{prg} #{args}"
            end
      result = Rvim::Filter.run(cmd, shell: editor.settings.get(:shell), shellcmdflag: editor.settings.get(:shellcmdflag))
      output = result.stdout.to_s
      gfm = editor.settings.get(:grepformat).to_s
      gfm = editor.settings.get(:errorformat).to_s if gfm.empty?
      entries = Rvim::Errorformat.parse(output, gfm)
      editor.quickfix.set(entries)
      if entries.empty?
        editor.status_message = "E480: No match: #{args}"
      else
        editor.status_message = "(1 of #{entries.size}) #{format_quickfix_summary(entries.first)}"
        jump_to_quickfix_entry(editor, entries.first) unless parsed.bang
      end
    end

    def self.execute_bufdo(editor, parsed)
      cmd = parsed.arg.to_s
      return if cmd.empty?

      saved = editor.current_buffer
      editor.buffer_order.each do |id|
        buf = editor.buffers[id]
        next unless buf

        editor.swap_to_buffer(buf)
        execute(editor, parse(cmd))
      end
      editor.swap_to_buffer(saved) if saved && editor.buffers.values.include?(saved)
    end

    def self.execute_tabdo(editor, parsed)
      cmd = parsed.arg.to_s
      return if cmd.empty?

      saved_idx = editor.current_tab_index
      editor.tabs.size.times do |i|
        editor.swap_to_tab(i)
        execute(editor, parse(cmd))
      end
      editor.swap_to_tab(saved_idx) if saved_idx && saved_idx < editor.tabs.size
    end

    def self.execute_windo(editor, parsed)
      cmd = parsed.arg.to_s
      return if cmd.empty?

      saved = editor.current_window
      editor.windows.dup.each do |win|
        editor.send(:activate_window, win)
        execute(editor, parse(cmd))
      end
      editor.send(:activate_window, saved) if saved && editor.windows.include?(saved)
    end

    def self.execute_argdo(editor, parsed)
      cmd = parsed.arg.to_s
      return if cmd.empty?

      editor.arg_list.each do |path|
        editor.open(path)
        execute(editor, parse(cmd))
      end
    end

    def self.execute_args(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        list = editor.arg_list
        if list.empty?
          editor.status_message = 'E163: there is no argument list'
        else
          editor.show_list(['Argument list', *list.each_with_index.map { |p, i| format('   %2d  %s', i + 1, p) }])
        end
        return
      end

      paths = arg.split(/\s+/).flat_map { |p| Dir.glob(p).empty? ? [p] : Dir.glob(p) }
      editor.set_arg_list(paths)
    end

    def self.execute_argadd(editor, parsed)
      arg = parsed.arg.to_s.strip
      return if arg.empty?

      arg.split(/\s+/).each { |p| editor.add_arg(p) }
    end

    def self.execute_tag(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.status_message = 'E471: usage: :tag NAME'
        return
      end

      editor.tag_jump(arg)
    end

    def self.format_tag_stack(editor)
      header = '   #  name              file:line'
      rows = editor.tag_stack.each_with_index.map do |e, i|
        format('   %2d  %-16s  %s:%d', i + 1, e[:name].to_s[0, 16], (e[:file] || '').to_s, e[:line_index] + 1)
      end
      ['Tag stack', header, *rows]
    end

    def self.execute_digraphs(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.show_list(format_digraphs)
        return
      end

      tokens = arg.split(/\s+/)
      pair, code_token = tokens
      if pair.nil? || pair.length != 2 || code_token.nil?
        editor.status_message = 'E471: usage: :digraph d1d2 N'
        return
      end

      code = code_token.to_i
      if code <= 0
        editor.status_message = 'E471: codepoint must be positive integer'
        return
      end

      Rvim::Digraphs.define(pair, code)
    end

    def self.format_digraphs
      header = '   pair  char  codepoint'
      rows = []
      Rvim::Digraphs.each do |pair, ch|
        rows << format('   %-4s  %-4s  U+%04X', pair, ch, ch.codepoints.first || 0)
      end
      ['Digraphs', header, *rows]
    end

    def self.execute_hi(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.show_list(format_highlights)
        return
      end

      tokens = arg.split(/\s+/)
      group = tokens.shift

      if group&.casecmp?('clear')
        if tokens.empty?
          Rvim::Highlights.reset_to_defaults!
        else
          Rvim::Highlights.clear(tokens.first)
        end
        return
      end

      attrs = {}
      tokens.each do |t|
        next unless t.include?('=')

        key, val = t.split('=', 2)
        case key.downcase
        when 'ctermfg' then attrs[:fg] = val
        when 'ctermbg' then attrs[:bg] = val
        when 'cterm', 'gui'
          val.to_s.split(',').each do |a|
            case a.downcase
            when 'bold' then attrs[:bold] = true
            when 'italic' then attrs[:italic] = true
            when 'underline' then attrs[:underline] = true
            when 'reverse', 'inverse' then attrs[:reverse] = true
            when 'none' then attrs.merge!(bold: false, italic: false, underline: false, reverse: false)
            end
          end
        end
      end

      Rvim::Highlights.set(group, **attrs)
    end

    def self.format_highlights
      header = '   group         fg              bg              attrs'
      rows = Rvim::Highlights.groups.map do |name, attr|
        attrs = []
        attrs << 'bold' if attr.bold
        attrs << 'italic' if attr.italic
        attrs << 'underline' if attr.underline
        attrs << 'reverse' if attr.reverse
        format(
          '   %-13s %-15s %-15s %s',
          name[0, 13],
          (attr.fg || '').to_s[0, 15],
          (attr.bg || '').to_s[0, 15],
          attrs.join(','),
        )
      end
      ['Highlight groups', header, *rows]
    end

    def self.execute_colorscheme(editor, parsed)
      name = parsed.arg.to_s.strip
      if name.empty?
        editor.status_message = 'colorscheme name required'
        return
      end

      if name == 'default'
        Rvim::Highlights.reset_to_defaults!
        return
      end

      paths = colorscheme_search_paths(name)
      target = paths.find { |p| File.exist?(p) }
      if target
        editor.source(target)
      else
        editor.status_message = "E185: Cannot find color scheme '#{name}'"
      end
    end

    def self.colorscheme_search_paths(name)
      [
        File.expand_path("~/.config/rvim/colors/#{name}.vim"),
        File.expand_path("~/.rvim/colors/#{name}.vim"),
      ]
    end

    def self.execute_diffthis(editor, _parsed)
      buf = editor.current_buffer
      return unless buf

      buf.diff_active = true
      editor.recompute_diff_status
    end

    def self.execute_diffoff(editor, parsed)
      bufs = parsed.bang ? editor.buffers.values : [editor.current_buffer].compact
      bufs.each do |b|
        b.diff_active = false
        b.diff_status = nil
      end
    end

    def self.execute_diffsplit(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.status_message = 'E32: No file name'
        return
      end

      current = editor.current_buffer
      current.diff_active = true if current
      editor.split_vertical
      editor.open(arg)
      editor.current_buffer.diff_active = true if editor.current_buffer
      editor.recompute_diff_status
    end

    def self.execute_lvimgrep(editor, parsed)
      list = current_location_list(editor)
      return unless list

      run_vimgrep(editor, parsed, list, label: 'location list')
    end

    def self.execute_lnext(editor, _parsed)
      list = current_location_list(editor)
      if list.nil? || list.empty?
        editor.status_message = 'E776: no location list'
        return
      end

      entry = list.advance(+1)
      jump_to_quickfix_entry(editor, entry)
      editor.status_message = "(#{list.index + 1} of #{list.size}) #{format_quickfix_summary(entry)}"
    end

    def self.execute_lprev(editor, _parsed)
      list = current_location_list(editor)
      if list.nil? || list.empty?
        editor.status_message = 'E776: no location list'
        return
      end

      entry = list.advance(-1)
      jump_to_quickfix_entry(editor, entry)
      editor.status_message = "(#{list.index + 1} of #{list.size}) #{format_quickfix_summary(entry)}"
    end

    def self.execute_ll(editor, parsed)
      list = current_location_list(editor)
      if list.nil? || list.empty?
        editor.status_message = 'E776: no location list'
        return
      end

      n = parsed.arg.to_s.strip
      idx = n.empty? ? list.index : n.to_i - 1
      entry = list.at(idx)
      if entry
        jump_to_quickfix_entry(editor, entry)
      else
        editor.status_message = 'E553: No more items'
      end
    end

    def self.execute_lmake(editor, parsed)
      list = current_location_list(editor)
      return unless list

      args = parsed.arg.to_s
      prg = editor.settings.get(:makeprg).to_s
      prg = 'make' if prg.empty?
      cmd = args.empty? ? prg : "#{prg} #{args}"
      result = Rvim::Filter.run(cmd, shell: editor.settings.get(:shell), shellcmdflag: editor.settings.get(:shellcmdflag))
      output = result.stdout.to_s + result.stderr.to_s
      entries = Rvim::Errorformat.parse(output, editor.settings.get(:errorformat))
      list.set(entries)
      report_list_status(editor, entries, parsed.bang, '(No errors)')
    end

    def self.execute_lgrep(editor, parsed)
      list = current_location_list(editor)
      return unless list

      args = parsed.arg.to_s.strip
      if args.empty?
        editor.status_message = 'E471: usage: :lgrep PATTERN [FILES]'
        return
      end

      prg = editor.settings.get(:grepprg).to_s
      prg = 'grep -n $* /dev/null' if prg.empty?
      cmd = prg.include?('$*') ? prg.sub('$*', args) : "#{prg} #{args}"
      result = Rvim::Filter.run(cmd, shell: editor.settings.get(:shell), shellcmdflag: editor.settings.get(:shellcmdflag))
      gfm = editor.settings.get(:grepformat).to_s
      gfm = editor.settings.get(:errorformat).to_s if gfm.empty?
      entries = Rvim::Errorformat.parse(result.stdout.to_s, gfm)
      list.set(entries)
      report_list_status(editor, entries, parsed.bang, "E480: No match: #{args}")
    end

    def self.current_location_list(editor)
      win = editor.current_window
      unless win
        editor.status_message = 'E776: no location list (no current window)'
        return nil
      end

      win.location_list
    end

    def self.report_list_status(editor, entries, bang, empty_message)
      if entries.empty?
        editor.status_message = empty_message
      else
        editor.status_message = "(1 of #{entries.size}) #{format_quickfix_summary(entries.first)}"
        jump_to_quickfix_entry(editor, entries.first) unless bang
      end
    end

    def self.format_location_list(editor)
      win = editor.current_window
      return ['No window'] unless win

      list = win.location_list
      header = '   #  file:line:col  text'
      rows = list.entries.each_with_index.map do |e, i|
        marker = i == list.index ? '>' : ' '
        format('%s %3d  %s:%d:%d  %s', marker, i + 1, e.file, e.line, e.col, e.text.to_s[0, 80])
      end
      ['Location list', header, *rows]
    end

    def self.run_vimgrep(editor, parsed, target_list, label:)
      arg = parsed.arg.to_s.strip
      m = VIMGREP_RE.match(arg)
      unless m
        editor.status_message = "E682: usage: :#{label.start_with?('loc') ? 'lvimgrep' : 'vimgrep'} /pattern/ {files}"
        return
      end

      begin
        pattern = Regexp.new(m[:pat])
      rescue RegexpError => e
        editor.status_message = "E383: Invalid pattern: #{e.message}"
        return
      end

      entries = []
      m[:files].split(/\s+/).each do |g|
        Dir.glob(g).each do |path|
          next unless File.file?(path)

          File.foreach(path).with_index do |line, i|
            md = pattern.match(line)
            next unless md

            entries << Rvim::Quickfix::Entry.new(
              file: path,
              line: i + 1,
              col: md.begin(0) + 1,
              text: line.chomp,
            )
          end
        end
      end

      target_list.set(entries)
      report_list_status(editor, entries, parsed.bang, "E480: No match: #{m[:pat]}")
    end

    VIMGREP_RE = %r{\A/(?<pat>(?:\\.|[^/])*)/\s+(?<files>.+)\z}.freeze

    def self.execute_vimgrep(editor, parsed)
      run_vimgrep(editor, parsed, editor.quickfix, label: 'quickfix')
    end

    def self.execute_cnext(editor, _parsed)
      qf = editor.quickfix
      if qf.empty?
        editor.status_message = 'E42: No Errors'
        return
      end

      entry = qf.advance(+1)
      jump_to_quickfix_entry(editor, entry)
      editor.status_message = "(#{qf.index + 1} of #{qf.size}) #{format_quickfix_summary(entry)}"
    end

    def self.execute_cprev(editor, _parsed)
      qf = editor.quickfix
      if qf.empty?
        editor.status_message = 'E42: No Errors'
        return
      end

      entry = qf.advance(-1)
      jump_to_quickfix_entry(editor, entry)
      editor.status_message = "(#{qf.index + 1} of #{qf.size}) #{format_quickfix_summary(entry)}"
    end

    def self.execute_cc(editor, parsed)
      qf = editor.quickfix
      if qf.empty?
        editor.status_message = 'E42: No Errors'
        return
      end

      n = parsed.arg.to_s.strip
      idx = n.empty? ? qf.index : n.to_i - 1
      entry = qf.at(idx)
      if entry
        jump_to_quickfix_entry(editor, entry)
        editor.status_message = "(#{qf.index + 1} of #{qf.size}) #{format_quickfix_summary(entry)}"
      else
        editor.status_message = "E553: No more items"
      end
    end

    def self.jump_to_quickfix_entry(editor, entry)
      return unless entry

      if entry.file && entry.file != editor.filepath
        editor.open(entry.file)
      end
      editor.push_jump
      editor.instance_variable_set(:@line_index, [entry.line - 1, 0].max)
      target_line = editor.buffer_of_lines[editor.line_index] || ''
      editor.instance_variable_set(:@byte_pointer, (entry.col - 1).clamp(0, target_line.bytesize))
    end

    def self.format_quickfix(editor)
      header = '   #  file:line:col  text'
      rows = []
      editor.quickfix.entries.each_with_index do |e, i|
        marker = i == editor.quickfix.index ? '>' : ' '
        rows << format('%s %3d  %s:%d:%d  %s', marker, i + 1, e.file, e.line, e.col, e.text.to_s[0, 80])
      end
      ['Quickfix', header, *rows]
    end

    def self.format_quickfix_summary(entry)
      "#{entry.file}:#{entry.line}:#{entry.col} #{entry.text.to_s[0, 60]}"
    end

    def self.execute_sort(editor, parsed)
      flags = parsed.arg.to_s
      numeric = flags.include?('n')
      ignorecase = flags.include?('i')
      uniq = flags.include?('u')

      range = parsed.range || :whole
      start_line, end_line = resolve_sub_range(editor, range)
      lines = editor.buffer_of_lines[start_line..end_line].dup

      sort_key = if numeric
                   ->(line) { line.to_s[/-?\d+/].to_i }
                 elsif ignorecase
                   ->(line) { line.to_s.downcase }
                 else
                   ->(line) { line.to_s }
                 end

      sorted = lines.sort_by(&sort_key)
      sorted.reverse! if parsed.bang
      sorted = sorted.uniq if uniq

      editor.replace_line_range(start_line, end_line, sorted)
    end

    def self.execute_autocmd(editor, parsed)
      arg = parsed.arg.to_s.strip

      if parsed.bang
        if arg.empty?
          editor.autocommands.clear_group(editor.autocommands.current_group)
          return
        end

        parts = arg.split(/\s+/, 3)
        events = parts[0].split(',')
        pattern = parts[1]
        events.each do |ev|
          editor.autocommands.remove(event: ev, pattern: pattern)
        end
        return
      end

      if arg.empty?
        editor.show_list(format_autocommands(editor))
        return
      end

      parts = arg.split(/\s+/, 3)
      if parts.size < 3
        editor.status_message = 'E471: Argument required: :autocmd events pattern command'
        return
      end

      events_token, patterns_token, command = parts
      events = events_token.split(',')
      patterns = patterns_token.split(',')
      editor.autocommands.add(events, patterns, command)
    end

    def self.execute_augroup(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty? || arg.casecmp?('END')
        editor.autocommands.current_group = nil
      else
        editor.autocommands.current_group = arg
      end
    end

    def self.format_autocommands(editor)
      header = '   group     event           pattern         command'
      rows = []
      editor.autocommands.each do |e|
        rows << format(
          '   %-9s %-15s %-15s %s',
          (e.group || '').to_s[0, 9],
          e.event.to_s[0, 15],
          e.pattern.to_s[0, 15],
          e.command.to_s,
        )
      end
      ['Autocommands', header, *rows]
    end

    def self.execute_bang(editor, parsed)
      cmd = parsed.arg.to_s
      if cmd.start_with?('!')
        if editor.last_bang_cmd
          cmd = editor.last_bang_cmd + cmd[1..]
        else
          editor.status_message = 'E34: no previous command'
          return
        end
      end
      cmd = expand_filenames(editor, cmd)
      editor.last_bang_cmd = cmd

      result = Rvim::Filter.run(cmd, shell: editor.settings.get(:shell), shellcmdflag: editor.settings.get(:shellcmdflag))
      if result.success?
        lines = result.stdout.chomp("\n").split("\n", -1)
        lines = ['(no output)'] if lines.empty? || lines == ['']
        editor.show_list(lines)
      else
        editor.status_message = filter_error_status(result)
      end
    end

    def self.execute_filter(editor, parsed)
      start_line, end_line = resolve_sub_range(editor, parsed.range)
      input = editor.buffer_of_lines[start_line..end_line].join("\n")
      cmd = expand_filenames(editor, parsed.arg.to_s)
      result = Rvim::Filter.run(cmd, input: input, shell: editor.settings.get(:shell), shellcmdflag: editor.settings.get(:shellcmdflag))
      unless result.success?
        editor.status_message = filter_error_status(result)
        return
      end

      out_lines = result.stdout.chomp("\n").split("\n", -1)
      out_lines = [''] if out_lines.empty?
      editor.replace_line_range(start_line, end_line, out_lines)
    end

    def self.execute_read(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.status_message = 'E32: No file name'
        return
      end

      if arg.start_with?('!')
        cmd = arg.sub(/\A!\s*/, '')
        result = Rvim::Filter.run(cmd, shell: editor.settings.get(:shell), shellcmdflag: editor.settings.get(:shellcmdflag))
        unless result.success?
          editor.status_message = filter_error_status(result)
          return
        end

        out_lines = result.stdout.chomp("\n").split("\n", -1)
        editor.insert_lines_after(editor.line_index, out_lines)
      else
        unless File.exist?(arg)
          editor.status_message = "E484: Can't open file #{arg}"
          return
        end

        out_lines = File.readlines(arg, chomp: true)
        editor.insert_lines_after(editor.line_index, out_lines)
      end
    end

    def self.filter_error_status(result)
      msg = result.stderr.lines.first&.chomp
      msg = "exit #{result.status.exitstatus}" if msg.nil? || msg.empty?
      "E: filter: #{msg[0, 60]}"
    end

    def self.execute_fold(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.create_fold_at_cursor(1)
        return
      end

      a, b = arg.split(/[,\s]+/, 2).map { |t| t.to_i }
      if a && b && a >= 1 && b >= 1
        editor.create_fold_over(a - 1, b - 1)
      else
        editor.status_message = 'E471: Argument required: :fold N,M'
      end
    end

    LET_RE = /\A(?<name>\w+)\s*=\s*(?<value>.*)\z/.freeze

    def self.execute_let(editor, parsed)
      arg = parsed.arg.to_s.strip
      m = LET_RE.match(arg)
      unless m
        editor.status_message = 'E121: Undefined variable: usage :let name = value'
        return
      end

      raw = m[:value].strip
      value = if raw.start_with?("'") && raw.end_with?("'") && raw.length >= 2
                raw[1..-2]
              elsif raw.start_with?('"') && raw.end_with?('"') && raw.length >= 2
                raw[1..-2]
              else
                raw
              end
      editor.let_vars[m[:name]] = value
    end

    def self.execute_mapclear(editor, parsed)
      modes = Rvim::Keymap.modes_for(parsed.verb, bang: parsed.bang)
      editor.keymap.clear(modes)
    end

    ABBREV_MODES = {
      abbrev: %i[insert cmdline],
      iabbrev: %i[insert],
      cabbrev: %i[cmdline],
      noreabbrev: %i[insert cmdline],
      inoreabbrev: %i[insert],
      cnoreabbrev: %i[cmdline],
      unabbrev: %i[insert cmdline],
      iunabbrev: %i[insert],
      cunabbrev: %i[cmdline],
      abclear: %i[insert cmdline],
      iabclear: %i[insert],
      cabclear: %i[cmdline],
    }.freeze

    def self.execute_abbrev(editor, parsed)
      arg = parsed.arg.to_s.strip
      modes = ABBREV_MODES[parsed.verb] || %i[insert cmdline]

      if arg.empty?
        editor.show_list(format_abbreviations(editor, modes))
        return
      end

      lhs, rhs = arg.split(/\s+/, 2)
      if rhs.nil? || rhs.empty?
        editor.show_list(format_abbreviations(editor, modes, lhs_filter: lhs))
        return
      end

      recursive = !%i[noreabbrev inoreabbrev cnoreabbrev].include?(parsed.verb)
      editor.abbreviations.add(modes, lhs, rhs, recursive: recursive)
    end

    def self.execute_unabbrev(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.status_message = 'E474: Argument required'
        return
      end

      modes = ABBREV_MODES[parsed.verb] || %i[insert cmdline]
      editor.abbreviations.remove(modes, arg)
    end

    def self.execute_abclear(editor, parsed)
      modes = ABBREV_MODES[parsed.verb] || %i[insert cmdline]
      editor.abbreviations.clear(modes)
    end

    def self.execute_runtime(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.status_message = 'E471: Argument required'
        return
      end

      bang = parsed.bang
      pattern = arg
      paths = runtime_paths(editor).flat_map do |dir|
        Dir.glob(File.expand_path(File.join(dir, pattern)))
      end.uniq

      if paths.empty?
        editor.status_message = "E484: Can't find file in 'runtimepath': #{pattern}"
        return
      end

      if bang
        paths.each { |p| editor.source(p) }
      else
        editor.source(paths.first)
      end
    end

    def self.execute_packadd(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.status_message = 'E471: Argument required'
        return
      end

      bang = parsed.bang
      home = File.expand_path('~/.vim')
      candidates = []
      candidates += Dir.glob(File.join(home, 'pack', '*', 'start', arg))
      candidates += Dir.glob(File.join(home, 'pack', '*', 'opt', arg))

      if candidates.empty?
        editor.status_message = "E919: Directory not found in 'packpath': #{arg}"
        return
      end

      pkg_dir = candidates.first
      # Append to runtimepath if not already present.
      rtp = editor.settings.get(:runtimepath).to_s
      unless rtp.split(',').include?(pkg_dir)
        editor.settings.set(:runtimepath, rtp.empty? ? pkg_dir : "#{rtp},#{pkg_dir}")
      end

      # Source plugin/*.vim files unless !bang (which loads structure only).
      return if bang

      Dir.glob(File.join(pkg_dir, 'plugin', '*.vim')).sort.each { |p| editor.source(p) }
    end

    def self.runtime_paths(editor)
      rtp = editor.settings.get(:runtimepath).to_s
      rtp.split(',').map { |p| File.expand_path(p.strip) }.reject(&:empty?)
    end

    ABBREV_MODE_TAGS = { insert: 'i', cmdline: 'c' }.freeze

    def self.format_abbreviations(editor, modes, lhs_filter: nil)
      header = '   mode  lhs                rhs'
      rows = []
      modes.each do |mode|
        editor.abbreviations.each(mode) do |lhs, entry|
          next if lhs_filter && lhs != lhs_filter

          tag = ABBREV_MODE_TAGS[mode] || ' '
          marker = entry.recursive ? ' ' : '*'
          rows << format('   %s%s    %-18s %s', tag, marker, lhs, entry.rhs)
        end
      end
      [header] + rows
    end

    def self.execute_write(editor, parsed)
      target = parsed.arg && !parsed.arg.empty? ? parsed.arg : editor.filepath
      if target.nil?
        editor.status_message = 'E32: No file name'
        return
      end
      editor.save(target)
      editor.status_message = "\"#{target}\" written"
    rescue => e
      editor.status_message = "E: #{e.message}"
    end

    def self.execute_quit(editor, parsed)
      if editor.windows.size > 1
        editor.close_current_window
        return
      end

      # Last window in the current tab. If more tabs exist, close the tab.
      if editor.tabs.size > 1
        editor.tab_close
        return
      end

      if any_modified?(editor) && !parsed.bang
        if editor.settings.get(:confirm)
          confirm_destructive_quit(editor)
        else
          editor.status_message = 'E37: No write since last change (add ! to override)'
        end
      else
        editor.quit!
      end
    end

    def self.execute_quit_all(editor, parsed)
      if any_modified?(editor) && !parsed.bang
        if editor.settings.get(:confirm)
          confirm_destructive_quit(editor)
        else
          editor.status_message = 'E37: No write since last change (add ! to override)'
        end
      else
        editor.quit!
      end
    end

    def self.confirm_destructive_quit(editor)
      editor.confirm_prompt('Save changes before closing?', %w[y n c]) do |choice|
        case choice
        when 'y'
          save_all_modified(editor)
          editor.quit! unless any_modified?(editor)
        when 'n'
          editor.quit!
        when 'c'
          editor.status_message = 'Cancelled'
        end
      end
    end

    def self.save_all_modified(editor)
      editor.send(:save_current_buffer) if editor.current_buffer
      editor.buffers.values.each do |b|
        next unless b.modified
        next unless b.filepath

        previous = editor.current_buffer
        editor.swap_to_buffer(b)
        editor.save
        editor.swap_to_buffer(previous) if previous && previous != b
      end
    end

    KIND_TAGS = { char: 'c', line: 'l', block: 'b' }.freeze

    def self.format_registers(editor, filter: nil)
      header = 'type  name  content'
      table = editor.instance_variable_get(:@registers).instance_variable_get(:@table) || {}
      rows = []
      # Order: " (unnamed), "0-"9 (numbered), "a-"z (named)
      ordered_keys = ['"', *('0'..'9'), *('a'..'z')].select { |k| table[k] }
      ordered_keys = ordered_keys & filter if filter && !filter.empty?
      ordered_keys.each do |name|
        entry = table[name]
        next unless entry

        kind = KIND_TAGS[entry.kind] || '?'
        text = entry.text.is_a?(Array) ? entry.text.join("\\n") : entry.text.to_s
        preview = text.gsub("\n", '\\n')[0, 60]
        rows << format('   %s   "%s   %s', kind, name, preview)
      end
      # Add "% if filepath set and not filtered out
      if editor.filepath && (filter.nil? || filter.empty? || filter.include?('%'))
        rows << format('   c   "%%   %s', editor.filepath[0, 60])
      end
      [header, *rows]
    end

    def self.format_jumps(editor)
      header = ' jump line  col  text'
      jumps = editor.jump_list || []
      idx = editor.jump_index || 0
      rows = jumps.each_with_index.map do |(line, col), i|
        marker = (i == idx) ? '>' : ' '
        text = (editor.buffer_of_lines[line] || '').lstrip[0, 60]
        format('%s %4d  %4d  %4d  %s', marker, jumps.size - i, line + 1, col, text)
      end
      [header, *rows]
    end

    def self.format_marks(editor)
      header = 'mark  line  col  file/text'
      rows = []
      # Local marks (a-z) — fetch from current buffer
      local = editor.instance_variable_get(:@marks).instance_variable_get(:@table)
      local.sort.each do |name, (line, col)|
        text = editor.buffer_of_lines[line].to_s.lstrip[0, 60]
        rows << format(' %s   %4d  %4d  %s', name, line + 1, col, text)
      end
      # Global marks (A-Z)
      global = editor.instance_variable_get(:@global_marks).instance_variable_get(:@table)
      global.sort.each do |name, (buf_id, line, col)|
        buf = editor.buffers[buf_id]
        info = buf ? buf.display_name : "(buffer #{buf_id})"
        rows << format(' %s   %4d  %4d  %s', name, line + 1, col, info)
      end
      [header, *rows]
    end

    def self.execute_tabmove(editor, parsed)
      arg = parsed.arg.to_s.strip
      return if editor.tabs.size <= 1

      src = editor.current_tab_index
      dst = if arg.empty?
              editor.tabs.size - 1
            elsif arg.start_with?('+', '-')
              src + arg.to_i
            else
              arg.to_i
            end
      editor.tab_move(dst)
    end

    def self.execute_resize(editor, parsed, vertical: false)
      arg = parsed.arg.to_s.strip
      return if arg.empty?

      axis = vertical ? :width : :height
      if arg.start_with?('+', '-')
        editor.resize_current(axis, arg.to_i)
      else
        editor.resize_to(axis, arg.to_i)
      end
    end

    def self.format_history(editor)
      header = '      #  cmd'
      hist = editor.ex_history
      rows = hist.each_with_index.map do |line, i|
        format('%7d  %s', i + 1, line)
      end
      ['Command Line History', header, *rows]
    end

    def self.format_buffers(editor)
      header = '  N  flags  Name'
      rows = editor.buffer_order.map do |id|
        b = editor.buffers[id]
        cur = (id == editor.current_buffer&.id) ? '%' : ' '
        mod = b.modified ? '+' : ' '
        format('%s %2d  %s     %s', cur, id, mod, b.display_name)
      end
      [header, *rows]
    end

    def self.execute_set(editor, parsed, local: false)
      messages = []
      target_buffer = local ? editor.current_buffer : nil
      Array(parsed.set_options).each do |name, value|
        if editor.settings.known?(name)
          editor.settings.set(name, value, buffer: target_buffer)
          normalized = editor.settings.normalize(name)
          if normalized == :foldmethod
            editor.rebuild_folds_for_method
          elsif normalized == :foldlevel
            editor.apply_fold_level
          end
        else
          messages << "E518: Unknown option: #{name}"
        end
      end
      editor.status_message = messages.join('; ') unless messages.empty?
    end

    def self.any_modified?(editor)
      editor.send(:save_current_buffer) if editor.current_buffer
      return true if editor.modified

      editor.buffers.values.any?(&:modified)
    end

    def self.execute_substitute(editor, parsed)
      sub = parsed.sub
      pattern_ic = sub[:ignorecase] || effective_sub_ignorecase(editor, sub[:pattern])
      pattern = compile_sub_pattern(sub[:pattern], ignorecase: pattern_ic)
      unless pattern
        editor.status_message = "E383: Invalid search string: #{sub[:pattern]}"
        return
      end

      replacement = sub[:replacement].to_s.gsub(/\\\//, '/')
      global = sub[:global]
      start_line, end_line = resolve_sub_range(editor, parsed.range)

      count = 0
      lines = 0
      (start_line..end_line).each do |i|
        line = editor.buffer_of_lines[i]
        new_line, n = if global
                        gsub = line.gsub(pattern) { count += 1; replacement }
                        [gsub, count]
                      else
                        replaced = false
                        s = line.sub(pattern) do
                          replaced = true
                          count += 1
                          replacement
                        end
                        [s, replaced ? 1 : 0]
                      end
        if new_line != line
          editor.buffer_of_lines[i] = new_line
          lines += 1
          editor.modified = true
        end
        _ = n
      end
      editor.status_message = "#{count} substitution#{count == 1 ? '' : 's'} on #{lines} line#{lines == 1 ? '' : 's'}"
    end

    def self.compile_sub_pattern(str, ignorecase: false)
      Regexp.new(str, ignorecase ? Regexp::IGNORECASE : 0)
    rescue RegexpError
      nil
    end

    def self.effective_sub_ignorecase(editor, pattern_str)
      Rvim::Search.effective_ignorecase(
        pattern_str,
        ignorecase: editor.settings.get(:ignorecase),
        smartcase: editor.settings.get(:smartcase),
      )
    end

    def self.resolve_sub_range(editor, range)
      last = editor.buffer_of_lines.size - 1
      case range
      when :current
        [editor.line_index, editor.line_index]
      when :whole
        [0, last]
      when :visual
        last_visual = editor.instance_variable_get(:@last_visual)
        if last_visual
          al = last_visual[:anchor][0]
          el = last_visual[:last_end][0]
          [[al, el].min, [al, el].max].map { |v| v.clamp(0, last) }
        else
          [editor.line_index, editor.line_index]
        end
      when Array
        a, b = range
        [(a - 1).clamp(0, last), (b - 1).clamp(0, last)]
      else
        [editor.line_index, editor.line_index]
      end
    end
  end
end
