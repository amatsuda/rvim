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

      tokens = str.split(/\s+/, 2)
      head = tokens[0]
      arg = tokens[1]
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
             when 'let' then :let
             when 'fold', 'fo' then :fold
             when 'autocmd', 'au' then :autocmd
             when 'augroup', 'aug' then :augroup
             else verb_str.to_sym
             end

      if verb == :set || verb == :setlocal
        set_options = parse_set(arg)
        return Parsed.new(verb: verb, arg: arg, bang: bang, line_number: nil, set_options: set_options)
      end

      Parsed.new(verb: verb, arg: arg, bang: bang, line_number: nil)
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
        editor.show_list(format_registers(editor))
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
      when :history
        editor.show_list(format_history(editor))
      when :map, :nmap, :vmap, :imap, :omap,
           :noremap, :nnoremap, :vnoremap, :inoremap, :onoremap
        execute_map(editor, parsed)
      when :unmap, :nunmap, :vunmap, :iunmap, :ounmap
        execute_unmap(editor, parsed)
      when :mapclear, :nmapclear, :vmapclear, :imapclear, :omapclear
        execute_mapclear(editor, parsed)
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
      else
        editor.status_message = "E492: Not an editor command: #{parsed.verb}"
      end
    end

    def self.execute_map(editor, parsed)
      arg = parsed.arg.to_s.strip
      modes = Rvim::Keymap.modes_for(parsed.verb)

      if arg.empty?
        editor.show_list(format_mappings(editor, modes))
        return
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
      editor.keymap.add(modes, lhs, rhs, recursive: recursive)
    end

    def self.execute_unmap(editor, parsed)
      arg = parsed.arg.to_s.strip
      if arg.empty?
        editor.status_message = 'E474: Invalid argument: usage: :unmap lhs'
        return
      end

      lhs = Rvim::Keymap.expand(arg, leader: editor.mapleader)
      modes = Rvim::Keymap.modes_for(parsed.verb)
      editor.keymap.remove(modes, lhs)
    end

    MODE_TAGS = {
      normal: 'n',
      visual: 'v',
      insert: 'i',
      op_pending: 'o',
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
      result = Rvim::Filter.run(parsed.arg.to_s)
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
      result = Rvim::Filter.run(parsed.arg.to_s, input: input)
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
        result = Rvim::Filter.run(cmd)
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
      modes = Rvim::Keymap.modes_for(parsed.verb)
      editor.keymap.clear(modes)
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
        editor.status_message = 'E37: No write since last change (add ! to override)'
      else
        editor.quit!
      end
    end

    def self.execute_quit_all(editor, parsed)
      if any_modified?(editor) && !parsed.bang
        editor.status_message = 'E37: No write since last change (add ! to override)'
      else
        editor.quit!
      end
    end

    KIND_TAGS = { char: 'c', line: 'l', block: 'b' }.freeze

    def self.format_registers(editor)
      header = 'type  name  content'
      table = editor.instance_variable_get(:@registers).instance_variable_get(:@table) || {}
      rows = []
      # Order: " (unnamed), "0-"9 (numbered), "a-"z (named)
      ordered_keys = ['"', *('0'..'9'), *('a'..'z')].select { |k| table[k] }
      ordered_keys.each do |name|
        entry = table[name]
        next unless entry

        kind = KIND_TAGS[entry.kind] || '?'
        text = entry.text.is_a?(Array) ? entry.text.join("\\n") : entry.text.to_s
        preview = text.gsub("\n", '\\n')[0, 60]
        rows << format('   %s   "%s   %s', kind, name, preview)
      end
      # Add "% if filepath set
      if editor.filepath
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
