# frozen_string_literal: true

module Rvim
  module Operations
    module_function

    def yank(editor, sel)
      buffer = editor.buffer_of_lines

      case sel.mode
      when :line
        text = buffer[sel.start_line..sel.end_line].join("\n")
        editor.set_clipboard(text, :line)
      when :char
        editor.set_clipboard(extract_char(buffer, sel), :char)
      when :block
        rows = []
        sel.each_segment(buffer) { |li, s, e| rows << buffer[li].byteslice(s, e - s).to_s }
        editor.set_clipboard(rows, :block)
      end

      editor.move_cursor_to(sel.start_line, sel.start_col)
    end

    def extract_char(buffer, sel)
      if sel.start_line == sel.end_line
        buffer[sel.start_line].byteslice(sel.start_col, sel.end_col - sel.start_col + 1).to_s
      else
        parts = []
        parts << buffer[sel.start_line].byteslice(sel.start_col, buffer[sel.start_line].bytesize - sel.start_col).to_s
        ((sel.start_line + 1)...sel.end_line).each { |i| parts << buffer[i].to_s }
        parts << buffer[sel.end_line].byteslice(0, sel.end_col + 1).to_s
        parts.join("\n")
      end
    end
  end
end
