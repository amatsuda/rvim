# frozen_string_literal: true

module Rvim
  module MatchMotion
    OPEN_TO_CLOSE = { '(' => ')', '[' => ']', '{' => '}' }.freeze
    CLOSE_TO_OPEN = OPEN_TO_CLOSE.invert.freeze
    BRACKETS = (OPEN_TO_CLOSE.keys + OPEN_TO_CLOSE.values).freeze

    # Returns [target_line, target_byte] or nil. The starting bracket is the
    # bracket at (line_index, byte_pointer); if not on a bracket, scans forward
    # on the current line to find the first one (vim semantics).
    def self.match_at(buffer_of_lines, line_index, byte_pointer)
      line = buffer_of_lines[line_index]
      return nil unless line

      start_byte = locate_starting_bracket(line, byte_pointer)
      return nil unless start_byte

      ch = line.byteslice(start_byte, 1)
      if OPEN_TO_CLOSE.key?(ch)
        scan_forward(buffer_of_lines, line_index, start_byte, ch, OPEN_TO_CLOSE[ch])
      elsif CLOSE_TO_OPEN.key?(ch)
        scan_backward(buffer_of_lines, line_index, start_byte, CLOSE_TO_OPEN[ch], ch)
      end
    end

    def self.locate_starting_bracket(line, byte_pointer)
      return nil if line.empty?

      pos = byte_pointer.clamp(0, line.bytesize - 1)
      ch = line.byteslice(pos, 1)
      return pos if BRACKETS.include?(ch)

      i = pos
      while i < line.bytesize
        c = line.byteslice(i, 1)
        return i if BRACKETS.include?(c)

        i += 1
      end
      nil
    end

    # `open_ch` is the bracket we started on; `close_ch` is its match. Walking
    # forward, depth starts at 1 (we counted the start). When it returns to 0
    # we found the match.
    def self.scan_forward(buffer_of_lines, line_index, start_byte, open_ch, close_ch)
      depth = 1
      li = line_index
      bp = start_byte + 1
      while li < buffer_of_lines.size
        line = buffer_of_lines[li]
        while bp < line.bytesize
          c = line.byteslice(bp, 1)
          if c == open_ch
            depth += 1
          elsif c == close_ch
            depth -= 1
            return [li, bp] if depth.zero?
          end
          bp += 1
        end
        li += 1
        bp = 0
      end
      nil
    end

    def self.scan_backward(buffer_of_lines, line_index, start_byte, open_ch, close_ch)
      depth = 1
      li = line_index
      bp = start_byte - 1
      while li >= 0
        line = buffer_of_lines[li]
        while bp >= 0
          c = line.byteslice(bp, 1)
          if c == close_ch
            depth += 1
          elsif c == open_ch
            depth -= 1
            return [li, bp] if depth.zero?
          end
          bp -= 1
        end
        li -= 1
        bp = li >= 0 ? buffer_of_lines[li].bytesize - 1 : -1
      end
      nil
    end
  end
end
