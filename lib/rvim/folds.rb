# frozen_string_literal: true

module Rvim
  class Folds
    Fold = Struct.new(:start_line, :end_line, :closed, :level) do
      def initialize(*args)
        super
        self.level ||= 1
      end
    end

    def initialize
      @folds = []
    end

    # Add a fold spanning [start_line, end_line] inclusive. Rejects if the
    # range overlaps an existing fold (no nesting in v1).
    def add(start_line, end_line, closed: true, level: nil)
      return nil if start_line > end_line

      # Allow proper containment (nesting). Reject only PARTIAL overlap.
      @folds.each do |f|
        next if contains?(f.start_line, f.end_line, start_line, end_line)
        next if contains?(start_line, end_line, f.start_line, f.end_line)
        return nil if ranges_overlap?(f.start_line, f.end_line, start_line, end_line)
      end

      fold = Fold.new(start_line, end_line, closed, level)
      @folds << fold
      @folds.sort_by!(&:start_line)
      fold
    end

    private def contains?(outer_s, outer_e, inner_s, inner_e)
      outer_s <= inner_s && inner_e <= outer_e
    end

    def at_line(line)
      # Innermost (smallest range) fold containing the line.
      matches = @folds.select { |f| f.start_line <= line && line <= f.end_line }
      matches.min_by { |f| f.end_line - f.start_line }
    end

    # True iff some closed fold contains line and line is not THAT fold's start.
    # Walks all folds (not just innermost) so a closed outer fold hides every
    # interior line including inner folds' start_lines.
    def hidden?(line)
      @folds.any? { |f| f.closed && f.start_line < line && line <= f.end_line }
    end

    def closed_at?(line)
      f = at_line(line)
      !f.nil? && f.closed
    end

    def open(line)
      f = at_line(line)
      f.closed = false if f
      f
    end

    def close(line)
      f = at_line(line)
      f.closed = true if f
      f
    end

    def toggle(line)
      f = at_line(line)
      f.closed = !f.closed if f
      f
    end

    def remove(line)
      f = at_line(line)
      @folds.delete(f) if f
      f
    end

    def clear
      @folds.clear
    end

    def open_all
      @folds.each { |f| f.closed = false }
    end

    def close_all
      @folds.each { |f| f.closed = true }
    end

    def each(&block)
      @folds.each(&block)
    end

    def empty?
      @folds.empty?
    end

    def size
      @folds.size
    end

    # Shift fold positions after a line insertion/removal. line is the
    # insertion point; delta is +N for inserts, -N for deletes.
    def shift_after(line, delta)
      survivors = []
      @folds.each do |f|
        if delta > 0
          f.start_line += delta if f.start_line > line
          f.end_line += delta if f.end_line >= line
          survivors << f
        else
          # delete: collapse or drop folds intersecting the removed range
          removed_start = line
          removed_end = line - delta - 1
          if removed_end < f.start_line
            f.start_line += delta
            f.end_line += delta
            survivors << f
          elsif removed_start > f.end_line
            survivors << f
          else
            # range intersects fold — drop it for v1 (simpler than remapping)
          end
        end
      end
      @folds = survivors
    end

    private

    def ranges_overlap?(a_start, a_end, b_start, b_end)
      !(a_end < b_start || a_start > b_end)
    end

    # Build top-level fold ranges from indentation. A run of consecutive
    # lines with leading-space-count >= shiftwidth becomes one fold,
    # anchored at the previous less-indented line. Blank lines inside a
    # run extend it.
    def self.from_indent(buffer_of_lines, shiftwidth)
      return [] if shiftwidth <= 0

      ranges = []
      in_fold = false
      fold_start = nil
      buffer_of_lines.each_with_index do |line, i|
        text = line.to_s
        if text.strip.empty?
          # blank lines continue the current fold
          next
        end

        indent = text.bytes.take_while { |b| b == 0x20 }.size
        indented = indent >= shiftwidth

        if indented
          unless in_fold
            fold_start = [i - 1, 0].max
            in_fold = true
          end
        elsif in_fold
          ranges << [fold_start, i - 1]
          in_fold = false
          fold_start = nil
        end
      end
      ranges << [fold_start, buffer_of_lines.size - 1] if in_fold && fold_start

      ranges
    end

    OPEN_MARKER = /\{\{\{/.freeze
    CLOSE_MARKER = /\}\}\}/.freeze

    # Scan a buffer for {{{ ... }}} fold markers and return [[start, end], ...].
    # Stack-based; mismatched markers are skipped.
    def self.from_markers(buffer_of_lines)
      ranges = []
      stack = []
      buffer_of_lines.each_with_index do |line, i|
        text = line.to_s
        text.scan(/(#{OPEN_MARKER}|#{CLOSE_MARKER})/) do |(marker, _)|
          if marker.start_with?('{')
            stack << i
          else
            start = stack.pop
            ranges << [start, i] if start && start < i
          end
        end
      end
      ranges
    end
  end
end
