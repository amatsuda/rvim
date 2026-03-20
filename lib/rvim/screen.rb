# frozen_string_literal: true

module Rvim
  class Screen
    SMCUP = "\e[?1049h"
    RMCUP = "\e[?1049l"
    HIDE_CURSOR = "\e[?25l"
    SHOW_CURSOR = "\e[?25h"
    CLEAR = "\e[2J"
    HOME = "\e[H"
    REVERSE_ON = "\e[7m"
    REVERSE_OFF = "\e[27m"
    DIM_ON = "\e[2m"
    DIM_OFF = "\e[22m"
    ERASE_LINE = "\e[2K"

    def initialize(editor)
      @editor = editor
      @rows = 24
      @cols = 80
    end

    def scroll_top
      @editor.current_window&.scroll_top || 0
    end

    def scroll_top=(value)
      @editor.current_window.scroll_top = value if @editor.current_window
    end

    def setup
      $stdout.write(SMCUP)
      $stdout.write(CLEAR)
      $stdout.write(HOME)
      $stdout.flush
    end

    def teardown
      $stdout.write(SHOW_CURSOR)
      $stdout.write(RMCUP)
      $stdout.flush
    end

    def render
      @rows, @cols = Reline::IOGate.get_screen_size
      layout_windows(@rows - 1, @cols)

      out = +HIDE_CURSOR
      @editor.windows.each { |win| out << render_window(win) }
      out << render_vertical_dividers
      out << move_to(@rows, 1) << ERASE_LINE << bottom_line

      cw = @editor.current_window
      if @editor.prompt_mode
        out << move_to(@rows, @editor.prompt_buffer.length + 2)
      elsif cw
        gw = gutter_width(cw.buffer)
        cursor_row = cw.row + (@editor.line_index - cw.scroll_top) + 1
        cursor_col = cw.col + gw + display_column(@editor.buffer_of_lines[@editor.line_index] || '', @editor.byte_pointer) + 1
        out << move_to(cursor_row, cursor_col)
      end
      out << SHOW_CURSOR

      $stdout.write(out)
      $stdout.flush
    end

    private

    def layout_windows(total_rows, total_cols)
      windows = @editor.windows
      return if windows.empty?

      if @editor.split_orientation == :vertical && windows.size > 1
        layout_vertical(windows, total_rows, total_cols)
      else
        layout_horizontal(windows, total_rows, total_cols)
      end
    end

    def layout_horizontal(windows, total_rows, total_cols)
      n = windows.size
      per = total_rows / n
      remainder = total_rows - per * n
      row = 0
      windows.each_with_index do |win, i|
        win.row = row
        win.col = 0
        win.height = per + (i < remainder ? 1 : 0)
        win.width = total_cols
        row += win.height
      end
    end

    def layout_vertical(windows, total_rows, total_cols)
      n = windows.size
      # Reserve n-1 columns for dividers.
      content_cols = total_cols - (n - 1)
      per = content_cols / n
      remainder = content_cols - per * n
      col = 0
      windows.each_with_index do |win, i|
        win.row = 0
        win.col = col
        win.height = total_rows
        win.width = per + (i < remainder ? 1 : 0)
        col += win.width + 1 # +1 for the divider
      end
    end

    def render_window(win)
      buffer = win.buffer
      content_rows = win.height - 1
      adjust_window_scroll(win, content_rows)
      is_current = (win.equal?(@editor.current_window))
      gw = gutter_width(buffer)
      content_width = win.width - gw
      cursor_idx = is_current ? @editor.line_index : buffer.line_index

      out = +''
      content_rows.times do |i|
        idx = win.scroll_top + i
        line = if idx < buffer.lines.size
                 render_line(buffer.lines[idx])
               else
                 '~'
               end
        gutter = gutter_text(idx, cursor_idx, buffer.lines.size, gw, idx < buffer.lines.size)
        rendered = if is_current
                     apply_current_highlights(line, idx, content_width)
                   else
                     truncate(line, content_width)
                   end
        out << move_to(win.row + i + 1, win.col + 1)
        out << gutter << rendered.ljust(content_width)
      end

      # Per-window status row at the bottom of the window.
      out << move_to(win.row + win.height, win.col + 1)
      out << (is_current ? REVERSE_ON : DIM_ON + REVERSE_ON)
      out << truncate(window_status(win, is_current), win.width).ljust(win.width)
      out << REVERSE_OFF
      out << DIM_OFF unless is_current
      out
    end

    def render_vertical_dividers
      return '' unless @editor.split_orientation == :vertical
      return '' if @editor.windows.size < 2

      out = +''
      @editor.windows[0..-2].each do |win|
        col = win.col + win.width + 1
        win.height.times do |i|
          out << move_to(win.row + i + 1, col) << '│'
        end
      end
      out
    end

    def gutter_width(buffer)
      return 0 unless @editor.settings.get(:number) || @editor.settings.get(:relativenumber)

      digits = Math.log10([buffer.lines.size, 1].max).floor + 1
      [digits.clamp(2, 6) + 1, 4].max
    end

    def gutter_text(idx, cursor_idx, total, gw, has_line)
      return '' if gw.zero?

      number = if !has_line
                 ''
               elsif @editor.settings.get(:relativenumber) && idx != cursor_idx
                 (idx - cursor_idx).abs.to_s
               else
                 (idx + 1).to_s
               end
      DIM_ON + number.rjust(gw - 1) + ' ' + DIM_OFF
    end

    def adjust_window_scroll(win, visible)
      buffer = win.buffer
      cursor_line = (win == @editor.current_window) ? @editor.line_index : buffer.line_index
      if cursor_line < win.scroll_top
        win.scroll_top = cursor_line
      elsif cursor_line >= win.scroll_top + visible
        win.scroll_top = cursor_line - visible + 1
      end
      win.scroll_top = 0 if win.scroll_top.negative?
    end

    def apply_current_highlights(line, idx, width)
      sel = @editor.selection
      hl = @editor.settings.get(:hlsearch) || @editor.prompt_mode == :search_forward || @editor.prompt_mode == :search_backward
      matches = hl ? (@editor.search_matches || []) : []
      if sel
        apply_selection_highlight(line, idx, sel, width)
      elsif matches.any? { |l, _, _| l == idx }
        apply_search_highlight(line, idx, matches, width)
      else
        truncate(line, width)
      end
    end

    def render_line(line)
      line.gsub("\t", '        ')
    end

    def apply_selection_highlight(line, line_index, sel, width)
      case sel.mode
      when :line
        if line_index.between?(sel.start_line, sel.end_line)
          REVERSE_ON + truncate(line, width).ljust(width) + REVERSE_OFF
        else
          truncate(line, width)
        end
      when :char
        first, last = char_segment_bounds(line, line_index, sel)
        return truncate(line, width) unless first

        splice_highlight(line, first, last, width)
      when :block
        if line_index.between?(sel.start_line, sel.end_line)
          first = [sel.start_col, line.bytesize].min
          last = [sel.end_col + 1, line.bytesize].min
          splice_highlight(line, first, last, width)
        else
          truncate(line, width)
        end
      end
    end

    def char_segment_bounds(line, line_index, sel)
      return nil unless line_index.between?(sel.start_line, sel.end_line)

      first = line_index == sel.start_line ? sel.start_col : 0
      last = line_index == sel.end_line ? sel.end_col + 1 : line.bytesize
      [first, [last, line.bytesize].min]
    end

    def apply_search_highlight(line, line_index, matches, width)
      ranges = matches.select { |l, _, _| l == line_index }.map { |_, s, e| [s, e] }
      out = line.dup
      ranges.sort_by { |s, _| -s }.each do |s, e|
        first = [s, out.bytesize].min
        last = [e + 1, out.bytesize].min
        head = out.byteslice(0, first) || +''
        mid = out.byteslice(first, last - first) || +''
        tail = out.byteslice(last, out.bytesize - last) || +''
        out = head + REVERSE_ON + mid + REVERSE_OFF + tail
      end
      truncate(out, width + ranges.size * (REVERSE_ON.bytesize + REVERSE_OFF.bytesize))
    end

    def splice_highlight(line, first, last, width)
      first = [first, line.bytesize].min
      last = [last, line.bytesize].min
      head = line.byteslice(0, first) || ''
      mid = line.byteslice(first, last - first) || ''
      tail = line.byteslice(last, line.bytesize - last) || ''
      truncate(head + REVERSE_ON + mid + REVERSE_OFF + tail, width + REVERSE_ON.size + REVERSE_OFF.size)
    end

    def window_status(win, is_current)
      buffer = win.buffer
      mode = is_current ? mode_label : ''
      name = buffer.display_name
      modified = (is_current ? @editor.modified : buffer.modified) ? ' [+]' : ''
      recording = is_current && @editor.recording_macro ? "  recording @#{@editor.recording_macro}" : ''
      total = (is_current ? @editor.buffer_of_lines : buffer.lines).size
      ln = (is_current ? @editor.line_index : buffer.line_index) + 1
      col = (is_current ? @editor.byte_pointer : buffer.byte_pointer) + 1
      pct = total.zero? ? 0 : (ln * 100 / total)
      " #{mode} #{name}#{modified}    #{ln},#{col}    #{pct}%#{recording}".lstrip.then { |s| " #{s}" }
    end

    def mode_label
      case @editor.visual_mode
      when :char then '[Visual]'
      when :line then '[Visual Line]'
      when :block then '[Visual Block]'
      else
        case @editor.editing_mode_label
        when :vi_insert then '[Insert]'
        when :vi_command then '[Normal]'
        when :emacs then '[Emacs]'
        else "[#{@editor.editing_mode_label}]"
        end
      end
    end

    def bottom_line
      case @editor.prompt_mode
      when :ex then ":#{@editor.prompt_buffer}"
      when :search_forward then "/#{@editor.prompt_buffer}"
      when :search_backward then "?#{@editor.prompt_buffer}"
      else
        @editor.status_message ? @editor.status_message.to_s : ''
      end
    end

    def display_column(line, byte_pointer)
      Reline::Unicode.calculate_width(line.byteslice(0, byte_pointer) || '')
    end

    def truncate(str, width)
      return str if str.length <= width

      str[0, width]
    end

    def move_to(row, col)
      "\e[#{row};#{col}H"
    end
  end
end
