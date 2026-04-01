# frozen_string_literal: true

module Rvim
  class Folds
    Fold = Struct.new(:start_line, :end_line, :closed)

    def initialize
      @folds = []
    end

    # Add a fold spanning [start_line, end_line] inclusive. Rejects if the
    # range overlaps an existing fold (no nesting in v1).
    def add(start_line, end_line, closed: true)
      return nil if start_line > end_line
      return nil if @folds.any? { |f| ranges_overlap?(f.start_line, f.end_line, start_line, end_line) }

      fold = Fold.new(start_line, end_line, closed)
      @folds << fold
      @folds.sort_by!(&:start_line)
      fold
    end

    def at_line(line)
      @folds.find { |f| f.start_line <= line && line <= f.end_line }
    end

    # True iff line lies inside a closed fold but is not its start_line.
    def hidden?(line)
      f = at_line(line)
      !f.nil? && f.closed && line != f.start_line
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
  end
end
