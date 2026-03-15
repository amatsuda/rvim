# frozen_string_literal: true

module Rvim
  class Marks
    def initialize
      @table = {}
    end

    def set(name, line, col)
      return unless name =~ /\A[a-z]\z/

      @table[name] = [line, col]
    end

    def clear
      @table.clear
    end

    # Resolves a mark name to [line, col] or nil. Special marks are
    # delegated to the editor for live computation.
    def get(name, editor)
      case name
      when "'", '`'
        editor.previous_jump_position
      when '<', '>'
        editor.visual_position(name)
      when /\A[a-z]\z/
        @table[name]
      end
    end
  end
end
