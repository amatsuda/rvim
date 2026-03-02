# frozen_string_literal: true

module Rvim
  class Command
    Parsed = Struct.new(:verb, :arg, :bang, :line_number, keyword_init: true)

    def self.parse(input)
      str = input.to_s.dup
      str = str[1..] if str.start_with?(':')
      str.strip!
      return nil if str.empty?

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
             when 'wq' then :wq
             when 'x' then :wq
             when 'e', 'edit' then :e
             else verb_str.to_sym
             end

      Parsed.new(verb: verb, arg: arg, bang: bang, line_number: nil)
    end

    def self.execute(editor, parsed)
      return unless parsed

      case parsed.verb
      when :w
        execute_write(editor, parsed)
      when :q
        execute_quit(editor, parsed)
      when :wq
        execute_write(editor, parsed)
        editor.quit!
      when :e
        if parsed.arg.nil? || parsed.arg.empty?
          editor.status_message = 'E32: No file name'
        else
          editor.open(parsed.arg)
        end
      when :goto
        last = editor.buffer_of_lines.size - 1
        target = (parsed.line_number - 1).clamp(0, last)
        editor.instance_variable_set(:@line_index, target)
        editor.instance_variable_set(:@byte_pointer, 0)
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
      if editor.modified && !parsed.bang
        editor.status_message = 'E37: No write since last change (add ! to override)'
      else
        editor.quit!
      end
    end
  end
end
