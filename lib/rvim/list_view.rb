# frozen_string_literal: true

module Rvim
  class ListView
    attr_reader :lines, :cursor

    def initialize(lines)
      @lines = lines
      @cursor = 0
    end

    # Visible rows for the list. Caller passes the total rows allocated; we
    # subtract 1 for the "-- More --" prompt at the bottom.
    def page_size(rows)
      [rows - 1, 1].max
    end

    def page(rows)
      @lines[@cursor, page_size(rows)] || []
    end

    def more?(rows)
      @cursor + page_size(rows) < @lines.size
    end

    def advance!(rows)
      @cursor += page_size(rows)
    end

    def empty?
      @lines.empty?
    end
  end
end
