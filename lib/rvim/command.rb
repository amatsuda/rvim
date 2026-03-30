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

    def self.parse(input)
      str = input.to_s.dup
      str = str[1..] if str.start_with?(':')
      str.strip!
      return nil if str.empty?

      if (m = SUBSTITUTE_RE.match(str))
        return Parsed.new(
          verb: :sub,
          range: parse_range(m[:range]),
          sub: { pattern: m[:pat], replacement: m[:rep], global: m[:flags].to_s.include?('g') },
          arg: nil,
          bang: false,
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
        editor.instance_variable_set(:@byte_pointer, 0)
      when :sub
        execute_substitute(editor, parsed)
      when :source
        if parsed.arg.nil? || parsed.arg.empty?
          editor.status_message = 'E471: Argument required'
        else
          editor.source(parsed.arg)
        end
      else
        editor.status_message = "E492: Not an editor command: #{parsed.verb}"
      end
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
      pattern = compile_sub_pattern(sub[:pattern])
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

    def self.compile_sub_pattern(str)
      Regexp.new(str)
    rescue RegexpError
      nil
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
