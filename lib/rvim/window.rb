# frozen_string_literal: true

module Rvim
  class Window
    attr_accessor :buffer, :scroll_top, :row, :col, :height, :width
    attr_accessor :extra_rows, :extra_cols
    attr_accessor :vars

    def initialize(buffer)
      @buffer = buffer
      @scroll_top = 0
      @row = 0
      @col = 0
      @height = 24
      @width = 80
      @extra_rows = 0
      @extra_cols = 0
      @location_list = nil
      @vars = {}
    end

    def location_list
      @location_list ||= Rvim::Quickfix.new
    end
  end
end
