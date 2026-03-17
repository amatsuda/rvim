# frozen_string_literal: true

module Rvim
  class Window
    attr_accessor :buffer, :scroll_top, :row, :col, :height, :width

    def initialize(buffer)
      @buffer = buffer
      @scroll_top = 0
      @row = 0
      @col = 0
      @height = 24
      @width = 80
    end
  end
end
