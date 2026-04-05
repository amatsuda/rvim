# frozen_string_literal: true

module Rvim
  module Modeline
    # vim: set option=value option=value :   (set form)
    # vim: option=value option=value         (no-set form)
    SET_FORM = /\b(?:vim|ex):\s*se?t?\s+(?<opts>.+?):/.freeze
    PLAIN_FORM = /\b(?:vim|ex):\s*(?<opts>.+?)(?::|$)/.freeze

    def self.parse(line)
      m = SET_FORM.match(line) || PLAIN_FORM.match(line)
      return nil unless m

      m[:opts].split(/[\s:]+/).reject(&:empty?)
    end

    def self.apply(editor, buffer)
      return unless editor.settings.get(:modeline)

      n = editor.settings.get(:modelines).to_i
      return if n <= 0

      lines = buffer.lines
      head = (0...[n, lines.size].min)
      tail_start = [lines.size - n, head.last.to_i + 1].max
      tail = (tail_start...lines.size)

      (head.to_a + tail.to_a).uniq.each do |i|
        line = lines[i]
        next unless line

        tokens = parse(line)
        next unless tokens

        apply_tokens(editor, buffer, tokens)
      end
    end

    def self.apply_tokens(editor, buffer, tokens)
      tokens.each do |tok|
        m = tok.match(Rvim::Command::SET_TOKEN_RE)
        next unless m

        name = m[2]
        value = if m[1] == 'no'
                  false
                elsif m[3]
                  m[3].match?(/\A\d+\z/) ? m[3].to_i : m[3]
                else
                  true
                end
        next unless editor.settings.known?(name)

        editor.settings.set(name, value, buffer: buffer)
      end
    end
  end
end
