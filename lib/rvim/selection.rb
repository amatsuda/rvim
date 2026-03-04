# frozen_string_literal: true

module Rvim
  class Selection
    attr_reader :mode, :start_line, :start_col, :end_line, :end_col

    def self.from(mode, anchor, cursor, buffer_of_lines)
      al, ac = anchor
      cl, cc = cursor
      sel = allocate
      sel.send(:initialize_from, mode, al, ac, cl, cc, buffer_of_lines)
      sel
    end

    def linewise?
      @mode == :line
    end

    def charwise?
      @mode == :char
    end

    def blockwise?
      @mode == :block
    end

    def includes?(line, col)
      return false if line < @start_line || line > @end_line

      case @mode
      when :line
        true
      when :char
        if @start_line == @end_line
          col >= @start_col && col <= @end_col
        elsif line == @start_line
          col >= @start_col
        elsif line == @end_line
          col <= @end_col
        else
          true
        end
      when :block
        col >= @start_col && col <= @end_col
      end
    end

    def each_segment(buffer_of_lines)
      (@start_line..@end_line).each do |li|
        line = buffer_of_lines[li] || ''
        case @mode
        when :line
          yield li, 0, line.bytesize
        when :char
          first = li == @start_line ? @start_col : 0
          last = li == @end_line ? @end_col + 1 : line.bytesize
          last = [last, line.bytesize].min
          first = [first, line.bytesize].min
          yield li, first, last
        when :block
          first = [@start_col, line.bytesize].min
          last = [@end_col + 1, line.bytesize].min
          yield li, first, last
        end
      end
    end

    private

    def initialize_from(mode, al, ac, cl, cc, buffer_of_lines)
      @mode = mode
      case mode
      when :line
        @start_line, @end_line = [al, cl].minmax
        @start_col = 0
        last_line = buffer_of_lines[@end_line] || ''
        @end_col = [last_line.bytesize - 1, 0].max
      when :char
        if al < cl || (al == cl && ac <= cc)
          @start_line, @start_col = al, ac
          @end_line, @end_col = cl, cc
        else
          @start_line, @start_col = cl, cc
          @end_line, @end_col = al, ac
        end
      when :block
        @start_line, @end_line = [al, cl].minmax
        @start_col, @end_col = [ac, cc].minmax
      else
        raise ArgumentError, "unknown selection mode: #{mode}"
      end
    end
  end
end
