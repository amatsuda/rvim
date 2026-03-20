# frozen_string_literal: true

module Rvim
  module Operations
    module_function

    def yank(editor, sel, op: :yank)
      buffer = editor.buffer_of_lines

      case sel.mode
      when :line
        text = buffer[sel.start_line..sel.end_line].join("\n")
        editor.set_clipboard(text, :line, op: op)
      when :char
        editor.set_clipboard(extract_char(buffer, sel), :char, op: op)
      when :block
        rows = []
        sel.each_segment(buffer) { |li, s, e| rows << buffer[li].byteslice(s, e - s).to_s }
        editor.set_clipboard(rows, :block, op: op)
      end

      editor.move_cursor_to(sel.start_line, sel.start_col)
    end

    def delete(editor, sel)
      yank(editor, sel, op: :delete)
      buffer = editor.buffer_of_lines

      case sel.mode
      when :line
        delete_lines(editor, sel)
      when :char
        delete_char(editor, sel)
      when :block
        delete_block(editor, sel)
      end

      ensure_buffer_nonempty(editor)
    end

    def change(editor, sel)
      mode = sel.mode
      yank(editor, sel, op: :change)
      buffer = editor.buffer_of_lines

      case mode
      when :line
        # Replace deleted block with one empty line, cursor there.
        buffer.slice!(sel.start_line, sel.end_line - sel.start_line + 1)
        buffer.insert(sel.start_line, String.new('', encoding: editor.encoding))
        editor.move_cursor_to(sel.start_line, 0)
      when :char
        delete_char(editor, sel)
      when :block
        delete_block(editor, sel)
      end
      ensure_buffer_nonempty(editor)
      editor.config.editing_mode = :vi_insert
    end

    def delete_lines(editor, sel)
      buffer = editor.buffer_of_lines
      buffer.slice!(sel.start_line, sel.end_line - sel.start_line + 1)
      editor.move_cursor_to(sel.start_line, 0)
    end

    def delete_char(editor, sel)
      buffer = editor.buffer_of_lines

      if sel.start_line == sel.end_line
        line = buffer[sel.start_line]
        head = line.byteslice(0, sel.start_col) || +''
        tail = line.byteslice(sel.end_col + 1, line.bytesize - sel.end_col - 1) || +''
        buffer[sel.start_line] = String.new(head + tail, encoding: line.encoding)
      else
        first_head = buffer[sel.start_line].byteslice(0, sel.start_col) || +''
        last_tail = buffer[sel.end_line].byteslice(sel.end_col + 1, buffer[sel.end_line].bytesize - sel.end_col - 1) || +''
        merged = String.new(first_head + last_tail, encoding: buffer[sel.start_line].encoding)
        buffer[sel.start_line..sel.end_line] = [merged]
      end
      editor.move_cursor_to(sel.start_line, sel.start_col)
    end

    def delete_block(editor, sel)
      buffer = editor.buffer_of_lines
      sel.each_segment(buffer) do |li, s, e|
        line = buffer[li]
        head = line.byteslice(0, s) || +''
        tail = line.byteslice(e, line.bytesize - e) || +''
        buffer[li] = String.new(head + tail, encoding: line.encoding)
      end
      editor.move_cursor_to(sel.start_line, sel.start_col)
    end

    def toggle_case(editor, sel)
      buffer = editor.buffer_of_lines
      sel.each_segment(buffer) do |li, s, e|
        line = buffer[li]
        head = line.byteslice(0, s) || +''
        mid = line.byteslice(s, e - s) || +''
        tail = line.byteslice(e, line.bytesize - e) || +''
        flipped = mid.chars.map { |c| c =~ /[A-Z]/ ? c.downcase : c =~ /[a-z]/ ? c.upcase : c }.join
        buffer[li] = String.new(head + flipped + tail, encoding: line.encoding)
      end
      editor.move_cursor_to(sel.start_line, sel.start_col)
    end

    def shift_right(editor, sel, count: 1)
      shiftwidth = editor.settings.get(:shiftwidth)
      indent = ' ' * (shiftwidth * count)
      (sel.start_line..sel.end_line).each do |i|
        line = editor.buffer_of_lines[i]
        editor.buffer_of_lines[i] = String.new(indent + line.to_s, encoding: editor.encoding)
      end
      editor.move_cursor_to(sel.start_line, 0)
    end

    def shift_left(editor, sel, count: 1)
      shiftwidth = editor.settings.get(:shiftwidth)
      strip = shiftwidth * count
      (sel.start_line..sel.end_line).each do |i|
        line = editor.buffer_of_lines[i]
        next unless line

        leading = line.bytes.take_while { |b| b == 0x20 }.size
        remove = [leading, strip].min
        editor.buffer_of_lines[i] = String.new(line.byteslice(remove, line.bytesize - remove) || '', encoding: editor.encoding)
      end
      editor.move_cursor_to(sel.start_line, 0)
    end

    def ensure_buffer_nonempty(editor)
      return unless editor.buffer_of_lines.empty?

      editor.buffer_of_lines << String.new('', encoding: editor.encoding)
      editor.move_cursor_to(0, 0)
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
