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

    # Toggle line-comments across the selection, NeoVim 0.10-style.
    #
    # Reads &commentstring (default "# %s"), splits on %s for prefix
    # and suffix. Direction is decided over the whole range: if every
    # non-blank line is already commented, uncomment all; otherwise
    # comment all. Indent is preserved.
    def toggle_comment(editor, sel)
      buffer = editor.buffer_of_lines
      cms = editor.settings.get(:commentstring).to_s
      cms = '# %s' if cms.empty? || !cms.include?('%s')
      prefix, suffix = cms.split('%s', 2)
      prefix = prefix.to_s
      suffix = suffix.to_s

      start_line, end_line = comment_line_range(sel, buffer)
      return if start_line.nil?

      lines = buffer[start_line..end_line] || []
      indices = (start_line..end_line).to_a

      # Find common indent of non-blank lines — used both as the
      # insertion point for the prefix and the lookup point when
      # detecting "already commented".
      common_indent = common_leading_indent(lines)

      # Direction: uncomment when *every* non-blank line matches.
      non_blank = lines.each_with_index.reject { |l, _| l.to_s.strip.empty? }
      all_commented = !non_blank.empty? && non_blank.all? { |l, _| commented?(l, common_indent, prefix, suffix) }

      indices.each_with_index do |buf_idx, i|
        line = lines[i].to_s
        next if line.strip.empty? && !all_commented

        buffer[buf_idx] = if all_commented
                            uncomment_line(line, common_indent, prefix, suffix, editor.encoding)
                          else
                            comment_line(line, common_indent, prefix, suffix, editor.encoding)
                          end
      end

      editor.move_cursor_to(start_line, 0)
    end

    def comment_line_range(sel, buffer)
      case sel.mode
      when :line, :char, :block
        [sel.start_line.clamp(0, [buffer.size - 1, 0].max),
         sel.end_line.clamp(0, [buffer.size - 1, 0].max)]
      end
    end

    def common_leading_indent(lines)
      indents = lines.reject { |l| l.to_s.strip.empty? }.map { |l| l.to_s[/\A[ \t]*/].length }
      indents.min || 0
    end

    def commented?(line, indent, prefix, suffix)
      body = line.to_s[indent..] || ''
      return false unless body.start_with?(prefix.rstrip) || body.start_with?(prefix)

      # Match the prefix loosely (with or without its trailing space),
      # so `#foo` and `# foo` both count as commented under `# %s`.
      stripped_prefix = prefix.rstrip
      head = body.start_with?(prefix) ? prefix : stripped_prefix
      remainder = body[head.length..]
      return true if suffix.empty?

      remainder.to_s.rstrip.end_with?(suffix.rstrip)
    end

    def comment_line(line, indent, prefix, suffix, encoding)
      str = line.to_s
      head = str[0, indent].to_s
      tail = str[indent..].to_s
      out = head + prefix + tail
      out = out + suffix unless suffix.empty?
      String.new(out, encoding: encoding)
    end

    def uncomment_line(line, indent, prefix, suffix, encoding)
      str = line.to_s
      head = str[0, indent].to_s
      body = str[indent..].to_s
      stripped_prefix = prefix.rstrip
      body = if body.start_with?(prefix)
               body[prefix.length..]
             elsif body.start_with?(stripped_prefix)
               body[stripped_prefix.length..]
             else
               body
             end
      unless suffix.empty?
        stripped_suffix = suffix.rstrip
        tail_re = /(?<lead>\s*)(?:#{Regexp.escape(suffix)}|#{Regexp.escape(stripped_suffix)})\z/
        body = body.sub(tail_re, '')
      end
      String.new(head + body, encoding: encoding)
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
        cut_end = Rvim::Selection.end_of_char_at(line, sel.end_col)
        head = line.byteslice(0, sel.start_col) || +''
        tail = line.byteslice(cut_end, line.bytesize - cut_end) || +''
        buffer[sel.start_line] = String.new(head + tail, encoding: line.encoding)
      else
        last_line = buffer[sel.end_line]
        cut_end = Rvim::Selection.end_of_char_at(last_line, sel.end_col)
        first_head = buffer[sel.start_line].byteslice(0, sel.start_col) || +''
        last_tail = last_line.byteslice(cut_end, last_line.bytesize - cut_end) || +''
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
      transform_case(editor, sel) do |c|
        c =~ /[A-Z]/ ? c.downcase : c =~ /[a-z]/ ? c.upcase : c
      end
    end

    def lowercase(editor, sel)
      transform_case(editor, sel, &:downcase)
    end

    def uppercase(editor, sel)
      transform_case(editor, sel, &:upcase)
    end

    def transform_case(editor, sel)
      buffer = editor.buffer_of_lines
      sel.each_segment(buffer) do |li, s, e|
        line = buffer[li]
        head = line.byteslice(0, s) || +''
        mid = line.byteslice(s, e - s) || +''
        tail = line.byteslice(e, line.bytesize - e) || +''
        transformed = mid.chars.map { |c| yield c }.join
        buffer[li] = String.new(head + transformed + tail, encoding: line.encoding)
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
        line = buffer[sel.start_line]
        cut_end = Rvim::Selection.end_of_char_at(line, sel.end_col)
        line.byteslice(sel.start_col, cut_end - sel.start_col).to_s
      else
        last_line = buffer[sel.end_line]
        cut_end = Rvim::Selection.end_of_char_at(last_line, sel.end_col)
        parts = []
        parts << buffer[sel.start_line].byteslice(sel.start_col, buffer[sel.start_line].bytesize - sel.start_col).to_s
        ((sel.start_line + 1)...sel.end_line).each { |i| parts << buffer[i].to_s }
        parts << last_line.byteslice(0, cut_end).to_s
        parts.join("\n")
      end
    end
  end
end
