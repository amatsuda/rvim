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
      seg_off, seg_text = segments[cur_seg_idx]
      byte_in_seg = byte_pointer - seg_off
      # Preserve the *display column* (terminal cells), not the byte offset,
      # so wrapping from "1234..." to "あいうえお" keeps the cursor's visual
      # column instead of dumping it mid-codepoint.
      desired_col = display_column_in(seg_text, byte_in_seg)

      if direction == :down
        if cur_seg_idx + 1 < segments.size
          land_on_segment(line_index, segments[cur_seg_idx + 1], desired_col)
        else
          return nil if line_index >= lines.size - 1

          next_line = lines[line_index + 1] || ''
          next_segs = splitter.call(next_line, width)
          land_on_segment(line_index + 1, next_segs[0], desired_col)
        end
      else
        if cur_seg_idx > 0
          land_on_segment(line_index, segments[cur_seg_idx - 1], desired_col)
        else
          return nil if line_index <= 0

          prev_line = lines[line_index - 1] || ''
          prev_segs = splitter.call(prev_line, width)
          land_on_segment(line_index - 1, prev_segs[-1], desired_col)
        end
      end
    end

    def self.locate_segment(segments, byte_pointer)
      return 0 if segments.empty?

      idx = (segments.size - 1).downto(0).find { |i| segments[i][0] <= byte_pointer }
      idx || 0
    end

    # Convert a desired display column into a byte offset within the
    # segment text, then return [line_index, absolute_byte].
    def self.land_on_segment(line_index, segment, desired_col)
      seg_off, seg_text = segment
      byte = byte_at_display_column(seg_text, desired_col)
      [line_index, seg_off + byte]
    end

    def self.display_column_in(text, byte_offset)
      slice = text.byteslice(0, [byte_offset, text.bytesize].min) || ''
      Reline::Unicode.calculate_width(slice.to_s)
    rescue ArgumentError
      0
    end

    # Walk grapheme clusters and stop on the one that covers target_col;
    # land at its start byte. If target_col is at/past EOL, clamp to the
    # last character's start byte.
    def self.byte_at_display_column(text, target_col)
      return 0 if text.nil? || text.empty? || target_col <= 0

      cur_col = 0
      cur_byte = 0
      text.grapheme_clusters.each do |gc|
        mbchar = gc.encode(Encoding::UTF_8)
        w = Reline::Unicode.get_mbchar_width(mbchar)
        return cur_byte if cur_col + w > target_col

        cur_col += w
        cur_byte += gc.bytesize
      end
      return 0 if cur_byte.zero?

      last_size = Reline::Unicode.get_prev_mbchar_size(text, cur_byte)
      [cur_byte - last_size, 0].max
    rescue ArgumentError
      0
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
