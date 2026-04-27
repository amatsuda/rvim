# frozen_string_literal: true

module Rvim
  class Tab
    attr_accessor :windows, :current_window, :split_orientation
    attr_accessor :vars

    def initialize(window)
      @windows = [window]
      @current_window = window
      @split_orientation = nil
      @vars = {}
    end

    def display_name
      buf = @current_window&.buffer
      return '[New]' unless buf

      File.basename(buf.display_name)
    end
  end
end
