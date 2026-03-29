# frozen_string_literal: true

module Rvim
  # Local marks (a-z) live in a Marks instance owned by each Buffer. Global
  # marks (A-Z) live in a separate Marks-like store on Editor; their entries
  # carry a buffer_id so jumps can switch buffers.
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

    def get(name, editor)
      case name
      when "'", '`'
        editor.previous_jump_position
      when '<', '>'
        editor.visual_position(name)
      when '.'
        editor.last_change_pos
      when '^'
        editor.last_insert_pos
      when '['
        editor.last_yank_range_start
      when ']'
        editor.last_yank_range_end
      when /\A[a-z]\z/
        @table[name]
      when /\A[A-Z]\z/
        editor.global_mark(name)
      end
    end
  end

  class GlobalMarks
    def initialize
      @table = {}
    end

    def set(name, buffer_id, line, col)
      return unless name =~ /\A[A-Z]\z/

      @table[name] = [buffer_id, line, col]
    end

    def get(name)
      @table[name.to_s.upcase] if name =~ /\A[A-Z]\z/i
    end

    def clear_buffer(buffer_id)
      @table.delete_if { |_, (bid, _, _)| bid == buffer_id }
    end
  end
end
