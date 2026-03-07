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

    # Stub — fleshed out in Stage 5.
    def bracket(editor, open_ch, close_ch, inclusive:)
      nil
    end

    # Stub — fleshed out in Stage 6.
    def paragraph(editor, inclusive:)
      nil
    end
  end
end
