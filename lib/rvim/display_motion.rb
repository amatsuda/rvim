# frozen_string_literal: true

module Rvim
  module DisplayMotion
    # Compute the next/prev position for display-line motion (gj/gk).
    # Returns [new_line_index, new_byte_pointer] or nil when at the buffer edge.
    # `splitter` is a callable: splitter.call(line_text, width) -> Array of
    # [byte_offset, segment_text].
    def self.next_position(lines, line_index, byte_pointer, width, direction, splitter:)
      return nil if width.nil? || width <= 0

      cur_line = lines[line_index] || ''
      segments = splitter.call(cur_line, width)
      cur_seg_idx = locate_segment(segments, byte_pointer)
      byte_in_seg = byte_pointer - segments[cur_seg_idx][0]

      if direction == :down
        if cur_seg_idx + 1 < segments.size
          land_on_segment(line_index, segments[cur_seg_idx + 1], byte_in_seg)
        else
          return nil if line_index >= lines.size - 1

          next_line = lines[line_index + 1] || ''
          next_segs = splitter.call(next_line, width)
          land_on_segment(line_index + 1, next_segs[0], byte_in_seg)
        end
      else
        if cur_seg_idx > 0
          land_on_segment(line_index, segments[cur_seg_idx - 1], byte_in_seg)
        else
          return nil if line_index <= 0

          prev_line = lines[line_index - 1] || ''
          prev_segs = splitter.call(prev_line, width)
          land_on_segment(line_index - 1, prev_segs[-1], byte_in_seg)
        end
      end
    end

    def self.locate_segment(segments, byte_pointer)
      return 0 if segments.empty?

      idx = (segments.size - 1).downto(0).find { |i| segments[i][0] <= byte_pointer }
      idx || 0
    end

    def self.land_on_segment(line_index, segment, desired_byte_in_seg)
      seg_off, seg_text = segment
      max_byte = [seg_text.bytesize - 1, 0].max
      byte = [desired_byte_in_seg, max_byte].min
      byte = 0 if byte.negative?
      byte = snap_back_to_char_boundary(seg_text, byte)
      [line_index, seg_off + byte]
    end

    # If `byte` lands on a UTF-8 continuation byte (10xxxxxx, 0x80-0xBF),
    # walk back to the leading byte of that codepoint so callers don't
    # produce mid-character cursor positions.
    def self.snap_back_to_char_boundary(text, byte)
      while byte.positive? && (b = text.getbyte(byte)) && b >= 0x80 && b < 0xC0
        byte -= 1
      end
      byte
    end
  end
end
