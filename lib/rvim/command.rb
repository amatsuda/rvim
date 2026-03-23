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
        editor.quit!
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
