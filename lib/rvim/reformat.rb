# frozen_string_literal: true

module Rvim
  module Reformat
    # Word-wrap a sequence of lines to a column width. Treats every blank
    # line as a paragraph separator: blank lines pass through and each
    # non-blank chunk is rewrapped independently.
    def self.wrap(lines, width)
      return lines.dup if width.nil? || width <= 0

      out = []
      buffer = []
      lines.each do |line|
        if line.to_s.strip.empty?
          out.concat(wrap_paragraph(buffer, width)) unless buffer.empty?
          out << ''
          buffer = []
        else
          buffer << line
        end
      end
      out.concat(wrap_paragraph(buffer, width)) unless buffer.empty?
      out
    end

    def self.wrap_paragraph(lines, width)
      text = lines.map(&:to_s).join(' ')
      words = text.split(/\s+/).reject(&:empty?)
      return [] if words.empty?

      result = []
      current = +''
      words.each do |w|
        if current.empty?
          current = w.dup
        elsif current.length + 1 + w.length <= width
          current << ' ' << w
        else
          result << current
          current = w.dup
        end
      end
      result << current unless current.empty?
      result
    end
  end
end
