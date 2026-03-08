# frozen_string_literal: true

module Rvim
  module Search
    module_function

    def scan(buffer_of_lines, pattern_str)
      pattern = compile(pattern_str)
      return [] unless pattern

      out = []
      buffer_of_lines.each_with_index do |line, line_idx|
        char_offset = 0
        while (m = pattern.match(line, char_offset))
          b = m.pre_match.bytesize
          e = b + m[0].bytesize
          if e == b
            # Zero-width match: step forward by one character to avoid infinite loop.
            char_offset = m.begin(0) + 1
            break if char_offset > line.length
          else
            out << [line_idx, b, e - 1]
            # Advance char_offset past this match.
            char_offset = m.end(0)
          end
        end
      end
      out
    end

    def next_match(matches, line, col, direction)
      return nil if matches.empty?

      case direction
      when :forward
        matches.find { |l, s, _| l > line || (l == line && s > col) } || matches.first
      when :backward
        matches.reverse_each.find { |l, _, e| l < line || (l == line && e < col) } || matches.last
      end
    end

    def compile(pattern_str)
      return nil if pattern_str.nil? || pattern_str.empty?

      Regexp.new(pattern_str)
    rescue RegexpError
      nil
    end
  end
end
