# frozen_string_literal: true

module Rvim
  class Window
    attr_accessor :buffer, :scroll_top, :row, :col, :height, :width
    attr_accessor :extra_rows, :extra_cols
    attr_accessor :vars
    # Floating-window attrs. `floating` flags this window as
    # detached from the tiling layout — the user supplies its
    # row/col/width/height directly via vim.api.nvim_open_win.
    # `border` is a symbol (:single, :double, :rounded, :solid)
    # or nil. `zindex` controls stacking among floats. `relative`
    # is 'editor' for V1; 'win' / 'cursor' anchors are deferred.
    # `focusable` lets a float take @current_window. `title` /
    # `footer` are short labels for the top / bottom borders.
    # `hide` skips rendering without destroying the window.
    attr_accessor :floating, :border, :zindex, :focusable, :relative
    attr_accessor :anchor, :title, :footer, :hide
    attr_reader :id

    @@next_id = 0
    @@id_mutex = Mutex.new
    def self.allocate_id
      @@id_mutex.synchronize { @@next_id += 1 }
    end

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
      @floating = false
      @border = nil
      @zindex = 50
      @focusable = true
      @relative = 'editor'
      @anchor = 'NW'
      @title = nil
      @footer = nil
      @hide = false
      @id = self.class.allocate_id
    end

    def floating?
      @floating == true
    end

    def location_list
      @location_list ||= Rvim::Quickfix.new
    end
  end
end
