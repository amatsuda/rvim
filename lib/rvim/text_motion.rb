# frozen_string_literal: true

module Rvim
  module TextMotion
    SENTENCE_END = /[.!?]/.freeze

    # Returns [line, byte] of the next sentence start. EOF clamps to end of
    # last line. Returns nil only for an empty buffer.
    def self.next_sentence(buffer, line_index, byte_pointer)
      return nil if buffer.empty?

      li = line_index
      bp = byte_pointer
      while li < buffer.size
        line = buffer[li] || ''
        # Find next sentence-end punctuation strictly after bp.
        i = bp
        while i < line.bytesize
          c = line.byteslice(i, 1)
          if c =~ SENTENCE_END
            j = i + 1
            j += 1 while j < line.bytesize && line.byteslice(j, 1) =~ /\s/
            if j < line.bytesize
              return [li, j]
            else
              # Skip to next non-blank line/byte.
              ni = li + 1
              while ni < buffer.size
                nl = buffer[ni] || ''
                k = 0
                k += 1 while k < nl.bytesize && nl.byteslice(k, 1) =~ /\s/
                return [ni, k] if k < nl.bytesize

                ni += 1
              end
              return [buffer.size - 1, [(buffer[-1] || '').bytesize - 1, 0].max]
            end
          end
          i += 1
        end
        li += 1
        bp = 0
      end
      [buffer.size - 1, [(buffer[-1] || '').bytesize - 1, 0].max]
    end

    def self.prev_sentence(buffer, line_index, byte_pointer)
      return nil if buffer.empty?

      # Walk backward; find the previous sentence-end punctuation strictly
      # before the cursor. The sentence-start we want is the first non-blank
      # AFTER that punctuation. If no punctuation found, jump to (0, first
      # non-blank).
      li = line_index
      bp = byte_pointer - 1
      while li >= 0
        line = buffer[li] || ''
        bp = line.bytesize - 1 if bp >= line.bytesize
        while bp >= 0
          c = line.byteslice(bp, 1)
          if c =~ SENTENCE_END
            # Sentence start = first non-blank after this punctuation.
            return advance_to_first_nonblank(buffer, li, bp + 1)
          end
          bp -= 1
        end
        li -= 1
        bp = li >= 0 ? (buffer[li] || '').bytesize - 1 : -1
      end

      # No prior sentence — jump to first non-blank in buffer.
      advance_to_first_nonblank(buffer, 0, 0)
    end

    def self.advance_to_first_nonblank(buffer, line_index, byte_pointer)
      li = line_index
      bp = byte_pointer
      while li < buffer.size
        line = buffer[li] || ''
        while bp < line.bytesize && line.byteslice(bp, 1) =~ /\s/
          bp += 1
        end
        return [li, bp] if bp < line.bytesize

        li += 1
        bp = 0
      end
      [buffer.size - 1, 0]
    end

    # Next blank line at or below line_index+1, or the last line if none.
    def self.next_paragraph(buffer, line_index)
      return 0 if buffer.empty?

      li = line_index + 1
      # Skip remaining non-blank lines after current.
      while li < buffer.size
        return li if blank?(buffer[li])

        li += 1
      end
      buffer.size - 1
    end

    # Previous blank line above, or line 0 if none.
    def self.prev_paragraph(buffer, line_index)
      return 0 if buffer.empty?

      li = line_index - 1
      while li >= 0
        return li if blank?(buffer[li])

        li -= 1
      end
      0
    end

    def self.blank?(line)
      line.nil? || line.to_s.strip.empty?
    end
  end
end
