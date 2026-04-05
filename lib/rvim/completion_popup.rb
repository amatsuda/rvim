# frozen_string_literal: true

module Rvim
  class CompletionPopup
    DEFAULT_MAX_HEIGHT = 8
    DEFAULT_MAX_WIDTH = 30

    attr_accessor :contents, :max_height, :max_width
    attr_reader :pointer, :scroll_top

    def initialize(contents:, pointer: 0, max_height: DEFAULT_MAX_HEIGHT, max_width: DEFAULT_MAX_WIDTH)
      @contents = contents
      @max_height = max_height
      @max_width = max_width
      @scroll_top = 0
      self.pointer = pointer
    end

    def pointer=(idx)
      @pointer = idx.to_i.clamp(0, [@contents.size - 1, 0].max)
      sync_scroll
    end

    def visible_height
      [@contents.size, @max_height].min
    end

    def visible_range
      return (0...0) if @contents.empty?

      bottom = [@scroll_top + visible_height, @contents.size].min
      @scroll_top...bottom
    end

    def width
      return 0 if @contents.empty?

      [@contents.map(&:length).max, @max_width].min
    end

    def empty?
      @contents.empty?
    end

    def size
      @contents.size
    end

    def needs_scrollbar?
      @contents.size > visible_height
    end

    private def sync_scroll
      return if @contents.empty?

      h = visible_height
      if @pointer < @scroll_top
        @scroll_top = @pointer
      elsif @pointer >= @scroll_top + h
        @scroll_top = @pointer - h + 1
      end
      @scroll_top = 0 if @scroll_top.negative?
    end
  end
end
