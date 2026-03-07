# frozen_string_literal: true

module Rvim
  module TextObject
    module_function

    def find(key, editor, inclusive:)
      char = key.is_a?(Integer) ? key.chr : key.to_s
      case char
      when 'w' then word(editor, inclusive: inclusive, big: false)
      when 'W' then word(editor, inclusive: inclusive, big: true)
      when '"', "'", '`' then quote(editor, char, inclusive: inclusive)
      when '(', ')', 'b' then bracket(editor, '(', ')', inclusive: inclusive)
      when '[', ']' then bracket(editor, '[', ']', inclusive: inclusive)
      when '{', '}', 'B' then bracket(editor, '{', '}', inclusive: inclusive)
      when '<', '>' then bracket(editor, '<', '>', inclusive: inclusive)
      when 'p' then paragraph(editor, inclusive: inclusive)
      end
    end

    def word(editor, inclusive:, big:)
      line_index = editor.line_index
      line = editor.buffer_of_lines[line_index] || ''
      return nil if line.bytesize.zero?

      pos = [editor.byte_pointer, line.bytesize - 1].min
      cls = char_class(line.byteslice(pos, 1), big)

      start_byte = pos
      while start_byte > 0 && char_class(line.byteslice(start_byte - 1, 1), big) == cls
        start_byte -= 1
      end

      end_byte = pos
      while end_byte < line.bytesize - 1 && char_class(line.byteslice(end_byte + 1, 1), big) == cls
        end_byte += 1
      end

      if inclusive
        if cls == :space
          # `aw` on whitespace: include the following word run too
          j = end_byte
          while j < line.bytesize - 1 && char_class(line.byteslice(j + 1, 1), big) != :space
            j += 1
          end
          end_byte = j
        else
          # `aw` on a word: include trailing whitespace, or leading if no trailing
          if end_byte < line.bytesize - 1 && char_class(line.byteslice(end_byte + 1, 1), big) == :space
            j = end_byte + 1
            while j < line.bytesize - 1 && char_class(line.byteslice(j + 1, 1), big) == :space
              j += 1
            end
            end_byte = j
          elsif start_byte > 0 && char_class(line.byteslice(start_byte - 1, 1), big) == :space
            j = start_byte - 1
            while j > 0 && char_class(line.byteslice(j - 1, 1), big) == :space
              j -= 1
            end
            start_byte = j
          end
        end
      end

      Rvim::Selection.from(:char, [line_index, start_byte], [line_index, end_byte], editor.buffer_of_lines)
    end

    def char_class(byte_slice, big)
      return :space if byte_slice.nil? || byte_slice.empty?

      ch = byte_slice
      if big
        ch =~ /\s/ ? :space : :word
      else
        case ch
        when /\s/ then :space
        when /\w/ then :word
        else :punct
        end
      end
    end

    def quote(editor, char, inclusive:)
      line_index = editor.line_index
      line = editor.buffer_of_lines[line_index] || ''
      pos = editor.byte_pointer

      # Find all unescaped occurrences of the quote on this line.
      positions = []
      i = 0
      while i < line.bytesize
        if line.byteslice(i, 1) == char && (i.zero? || line.byteslice(i - 1, 1) != '\\')
          positions << i
        end
        i += 1
      end
      return nil if positions.size < 2

      # Find the surrounding pair: largest open <= pos, smallest close > pos.
      open_pos = positions.select { |p| p <= pos }.last
      close_pos = positions.select { |p| p > (open_pos || -1) }.first
      # If cursor is on a quote and there's no enclosing pair, treat current as opening.
      if open_pos.nil? || close_pos.nil?
        # Try cursor-as-opening: pair up positions[0..1], [2..3], ...
        pair = positions.each_slice(2).find { |o, c| c && o <= pos && pos <= c }
        return nil unless pair

        open_pos, close_pos = pair
      end

      if inclusive
        # Extend by trailing whitespace, or leading if no trailing.
        end_pos = close_pos
        while end_pos < line.bytesize - 1 && line.byteslice(end_pos + 1, 1) == ' '
          end_pos += 1
        end
        start_pos = open_pos
        if end_pos == close_pos
          while start_pos > 0 && line.byteslice(start_pos - 1, 1) == ' '
            start_pos -= 1
          end
        end
        Rvim::Selection.from(:char, [line_index, start_pos], [line_index, end_pos], editor.buffer_of_lines)
      else
        return nil if close_pos - open_pos <= 1

        Rvim::Selection.from(:char, [line_index, open_pos + 1], [line_index, close_pos - 1], editor.buffer_of_lines)
      end
    end

    def bracket(editor, open_ch, close_ch, inclusive:)
      buffer = editor.buffer_of_lines
      cur_line = editor.line_index
      cur_col = editor.byte_pointer

      open_pos = find_unmatched_open(buffer, cur_line, cur_col, open_ch, close_ch)
      return nil unless open_pos

      close_pos = find_matching_close(buffer, open_pos[0], open_pos[1], open_ch, close_ch)
      return nil unless close_pos

      if inclusive
        Rvim::Selection.from(:char, open_pos, close_pos, buffer)
      else
        # Inner range: byte after open, byte before close.
        ol, oc = open_pos
        cl, cc = close_pos
        inner_start = next_byte(buffer, ol, oc)
        inner_end = prev_byte(buffer, cl, cc)
        return nil unless inner_start && inner_end

        # If open and close are adjacent (e.g. "()"), no inner range.
        if cl == ol && cc - oc <= 1
          return nil
        end

        Rvim::Selection.from(:char, inner_start, inner_end, buffer)
      end
    end

    def find_unmatched_open(buffer, line, col, open_ch, close_ch)
      # Walk backward from cursor; treat a close as +1 nesting, an open as -1.
      # Stop when nesting reaches -1 (an unmatched open).
      depth = 0
      l = line
      c = col
      # If cursor is on the close, walk left from one past the close to find its open.
      while l >= 0
        line_str = buffer[l] || ''
        c = line_str.bytesize - 1 if c.nil? || c >= line_str.bytesize
        while c >= 0
          ch = line_str.byteslice(c, 1)
          if ch == close_ch && !(l == line && c == col)
            depth += 1
          elsif ch == open_ch
            return [l, c] if depth.zero?

            depth -= 1
          end
          c -= 1
        end
        l -= 1
        c = nil
      end
      nil
    end

    def find_matching_close(buffer, line, col, open_ch, close_ch)
      depth = 0
      l = line
      c = col + 1
      while l < buffer.size
        line_str = buffer[l] || ''
        while c < line_str.bytesize
          ch = line_str.byteslice(c, 1)
          if ch == open_ch
            depth += 1
          elsif ch == close_ch
            return [l, c] if depth.zero?

            depth -= 1
          end
          c += 1
        end
        l += 1
        c = 0
      end
      nil
    end

    def next_byte(buffer, line, col)
      line_str = buffer[line] || ''
      if col + 1 < line_str.bytesize
        [line, col + 1]
      elsif line + 1 < buffer.size
        [line + 1, 0]
      end
    end

    def prev_byte(buffer, line, col)
      if col - 1 >= 0
        [line, col - 1]
      elsif line - 1 >= 0
        prev_line = buffer[line - 1] || ''
        [line - 1, [prev_line.bytesize - 1, 0].max]
      end
    end

    # Stub — fleshed out in Stage 6.
    def paragraph(editor, inclusive:)
      nil
    end
  end
end
