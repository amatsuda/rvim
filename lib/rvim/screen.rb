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
    DIFF_BG_ON = "\e[48;5;52m"
    DIFF_BG_OFF = "\e[49m"
    UNDERLINE_ON = "\e[4m"
    UNDERLINE_OFF = "\e[24m"
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
      reserved = @editor.prompt_mode == :listing ? list_overlay_rows + 1 : 1
      reserved_top = @editor.tabs.size > 1 ? 1 : 0
      layout_windows(@rows - reserved - reserved_top, @cols)
      if reserved_top.positive?
        @editor.windows.each { |w| w.row += reserved_top }
      end

      out = +HIDE_CURSOR
      out << render_tabline if reserved_top.positive?
      @editor.windows.each { |win| out << render_window(win) }
      out << render_vertical_dividers
      if @editor.prompt_mode == :listing
        out << render_listing_overlay
      end
      if @editor.cmdline_popup && !@editor.cmdline_popup.empty? && @editor.settings.get(:wildmenu)
        out << render_cmdline_popup
      end
      out << move_to(@rows, 1) << ERASE_LINE << bottom_line

      cw = @editor.current_window
      if @editor.prompt_mode
        out << move_to(@rows, @editor.prompt_buffer.length + 2)
      elsif cw
        gw = gutter_width(cw.buffer)
        content_width = cw.width - gw
        wrap_on = @editor.settings.get(:wrap)
        display_row_offset, display_col = cursor_display_position(cw, content_width, wrap_on)
        cursor_row = cw.row + display_row_offset + 1
        cursor_col = cw.col + gw + display_col + 1
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
      sizes = windows.each_with_index.map do |win, i|
        per + (i < remainder ? 1 : 0) + win.extra_rows
      end
      sizes = clamp_sizes(sizes, total_rows, min: 2)
      row = 0
      windows.each_with_index do |win, i|
        win.row = row
        win.col = 0
        win.height = sizes[i]
        win.width = total_cols
        row += win.height
      end
    end

    def layout_vertical(windows, total_rows, total_cols)
      n = windows.size
      content_cols = total_cols - (n - 1)
      per = content_cols / n
      remainder = content_cols - per * n
      sizes = windows.each_with_index.map do |win, i|
        per + (i < remainder ? 1 : 0) + win.extra_cols
      end
      sizes = clamp_sizes(sizes, content_cols, min: 4)
      col = 0
      windows.each_with_index do |win, i|
        win.row = 0
        win.col = col
        win.height = total_rows
        win.width = sizes[i]
        col += win.width + 1
      end
    end

    # Adjusts a list of sizes so each is at least `min` and the total matches `target`.
    # When extras push the total past target, take from oversized windows; when extras
    # pull below the minimum, give from oversized windows.
    def clamp_sizes(sizes, target, min:)
      sizes = sizes.map { |s| s < min ? min : s }
      total = sizes.sum
      diff = total - target
      while diff != 0
        if diff > 0
          # Shrink the largest window
          idx = sizes.index(sizes.max)
          break if sizes[idx] <= min

          sizes[idx] -= 1
          diff -= 1
        else
          idx = sizes.index(sizes.max)
          sizes[idx] += 1
          diff += 1
        end
      end
      sizes
    end

    def render_window(win)
      buffer = win.buffer
      content_rows = win.height - 1
      adjust_window_scroll(win, content_rows)
      is_current = (win.equal?(@editor.current_window))
      gw = gutter_width(buffer)
      content_width = win.width - gw
      cursor_idx = is_current ? @editor.line_index : buffer.line_index
      wrap_on = @editor.settings.get(:wrap)

      display_rows = build_display_rows(buffer, win.scroll_top, content_rows, content_width, wrap_on)

      cursorline_on = @editor.settings.get(:cursorline)
      out = +''
      display_rows.each_with_index do |row, i|
        line_idx, byte_off, segment, is_fold = row
        if line_idx.nil?
          gutter = ' ' * gw
          rendered = '~'
        elsif is_fold
          gutter = gutter_text(line_idx, cursor_idx, buffer.lines.size, gw, true)
          rendered = truncate_to_width(segment, content_width)
        else
          gutter = byte_off.zero? ? gutter_text(line_idx, cursor_idx, buffer.lines.size, gw, true) : (' ' * gw)
          full_line = render_line(buffer.lines[line_idx])
          rendered = if is_current
                       apply_current_highlights_segment(full_line, line_idx, byte_off, segment, content_width)
                     else
                       truncate_to_width(segment, content_width)
                     end
        end
        out << move_to(win.row + i + 1, win.col + 1)
        line_payload = gutter + pad_render_to_width(rendered, content_width)
        diff_on = !line_idx.nil? && buffer.diff_active && buffer.diff_status && buffer.diff_status[line_idx] == :differs
        line_payload = "#{DIFF_BG_ON}#{line_payload}#{DIFF_BG_OFF}" if diff_on
        if cursorline_on && is_current && line_idx == cursor_idx
          out << UNDERLINE_ON << line_payload << UNDERLINE_OFF
        else
          out << line_payload
        end
      end

      # Per-window status row at the bottom of the window.
      out << move_to(win.row + win.height, win.col + 1)
      out << (is_current ? REVERSE_ON : DIM_ON + REVERSE_ON)
      out << pad_to_width(truncate_to_width(window_status(win, is_current), win.width), win.width)
      out << REVERSE_OFF
      out << DIM_OFF unless is_current

      if is_current && @editor.completion_popup && !@editor.completion_popup.empty?
        out << render_completion_popup(win, gw, content_width, wrap_on)
      end
      out
    end

    def render_cmdline_popup
      popup = @editor.cmdline_popup
      visible = popup.visible_height
      need_bar = popup.needs_scrollbar?
      width = popup.width
      total_width = width + (need_bar ? 1 : 0)
      base_row = @rows - visible
      base_col = 1
      max_col = @cols
      base_col = [base_col, max_col - total_width + 1].max
      base_col = 1 if base_col < 1

      out = +''
      popup.visible_range.each_with_index do |idx, i|
        candidate = popup.contents[idx].to_s
        line = pad_to_width(truncate_to_width(candidate, width), width)
        line_with_bar = line + (need_bar ? scrollbar_glyph_for(popup, idx) : '')
        out << move_to(base_row + i, base_col)
        if idx == popup.pointer
          out << REVERSE_ON << line_with_bar << REVERSE_OFF
        else
          out << DIM_ON << line_with_bar << DIM_OFF
        end
      end
      out
    end

    def render_completion_popup(win, gw, content_width, wrap_on)
      popup = @editor.completion_popup
      cursor_row, _cursor_col = cursor_display_position(win, content_width, wrap_on)

      # Anchor at the column of the partial-word base, not the cursor column.
      base_byte = @editor.completion_base_byte || 0
      cursor_line = @editor.line_index
      buffer = win.buffer
      line_text = render_line(buffer.lines[cursor_line] || '')
      base_col = display_column(line_text, base_byte)

      width = popup.width
      visible = popup.visible_height
      need_bar = popup.needs_scrollbar?
      total_width = width + (need_bar ? 1 : 0)

      # Default: place below cursor row. Flip above if it would overflow window.
      base_row = win.row + cursor_row + 1
      if base_row + visible > win.row + win.height - 1
        base_row = (win.row + cursor_row - visible).clamp(win.row, win.row + win.height - 1)
      end
      start_col = win.col + gw + base_col + 1
      max_col = win.col + win.width
      start_col = [start_col, max_col - total_width + 1].min
      start_col = [start_col, win.col + 1].max

      out = +''
      popup.visible_range.each_with_index do |idx, i|
        candidate = popup.contents[idx].to_s
        line = pad_to_width(truncate_to_width(candidate, width), width)
        line_with_bar = line + (need_bar ? scrollbar_glyph_for(popup, idx) : '')
        row = base_row + i + 1
        out << move_to(row, start_col)
        if idx == popup.pointer
          out << REVERSE_ON << line_with_bar << REVERSE_OFF
        else
          out << DIM_ON << line_with_bar << DIM_OFF
        end
      end
      out
    end

    def scrollbar_glyph_for(popup, row_idx)
      total = popup.size
      visible = popup.visible_height
      return ' ' if total <= visible

      thumb_position = popup.scroll_top * (visible - 1) / [total - visible, 1].max
      relative = row_idx - popup.scroll_top
      relative == thumb_position ? '█' : '░'
    end

    # Returns Array<[line_idx_or_nil, byte_offset_within_line, segment_text, is_fold]>
    def build_display_rows(buffer, scroll_top, content_rows, content_width, wrap_on)
      rows = []
      line_idx = scroll_top
      folds_active = @editor.settings.get(:foldenable)
      folds = buffer.folds
      while rows.size < content_rows && line_idx < buffer.lines.size
        if folds_active && folds.hidden?(line_idx)
          line_idx += 1
          next
        end

        fold = folds_active ? folds.at_line(line_idx) : nil
        if fold && fold.closed && fold.start_line == line_idx
          rows << [line_idx, 0, fold_placeholder(buffer, fold, content_width), true]
          line_idx = fold.end_line + 1
          next
        end

        line = render_line(buffer.lines[line_idx])
        segments = wrap_on ? split_line_segments(line, content_width) : [[0, line]]
        segments.each do |off, seg|
          rows << [line_idx, off, seg, false]
          break if rows.size >= content_rows
        end
        line_idx += 1
      end
      rows << [nil, 0, '~', false] while rows.size < content_rows
      rows
    end

    def fold_placeholder(buffer, fold, content_width)
      n = fold.end_line - fold.start_line + 1
      first = buffer.lines[fold.start_line].to_s.lstrip
      str = format('+--%4d lines: %s', n, first)
      truncate_to_width(str, content_width)
    end

    # Split a line into [byte_offset, segment_text] pairs. Each segment's
    # display width is at most max_width.
    def split_line_segments(line, max_width)
      return [[0, line]] if max_width <= 0

      segments = []
      offset = 0
      total = line.bytesize
      while offset < total
        seg = take_display_width(line, offset, max_width)
        bytes = seg.bytesize
        if bytes.zero?
          # Defensive: if a single char doesn't fit, take one char anyway.
          ch = line.byteslice(offset, total - offset).each_char.first || ''
          bytes = ch.bytesize
          seg = ch
        end
        segments << [offset, seg]
        offset += bytes
      end
      segments << [0, ''] if segments.empty?
      segments
    end

    def take_display_width(line, byte_offset, max_width)
      out = +''
      current = 0
      remaining = line.byteslice(byte_offset, line.bytesize - byte_offset) || ''
      remaining.each_char do |c|
        cw = Reline::Unicode.calculate_width(c)
        break if current + cw > max_width

        out << c
        current += cw
      end
      out
    end

    # Highlight a specific segment of a buffer line. byte_off is the segment's
    # starting position within the full rendered line.
    #
    # For v1.13 Stage 1, when a line wraps (byte_off > 0), we render the segment
    # with syntax highlighting only — selection/search highlights would need
    # segment-local index arithmetic that's deferred. For non-wrapped lines
    # (byte_off == 0 AND segment is the full line) we fall through to the
    # existing apply_current_highlights which handles all three highlight types.
    def apply_current_highlights_segment(full_line, line_idx, byte_off, segment, content_width)
      if byte_off.zero? && segment.bytesize == full_line.bytesize
        apply_current_highlights(full_line, line_idx, content_width)
      else
        apply_syntax_highlight(segment, content_width)
      end
    end

    def cursor_display_position(win, content_width, wrap_on)
      buffer = win.buffer
      cursor_line = @editor.line_index
      cursor_byte = @editor.byte_pointer

      unless wrap_on
        line_text = render_line(buffer.lines[cursor_line] || '')
        return [cursor_line - win.scroll_top, display_column(line_text, cursor_byte)]
      end

      display_row = 0
      (win.scroll_top...cursor_line).each do |li|
        next if li >= buffer.lines.size

        line = render_line(buffer.lines[li] || '')
        display_row += split_line_segments(line, content_width).size
      end

      cursor_line_text = render_line(buffer.lines[cursor_line] || '')
      segments = split_line_segments(cursor_line_text, content_width)
      seg_idx = (segments.size - 1).downto(0).find { |i| segments[i][0] <= cursor_byte } || 0
      seg_offset, seg_text = segments[seg_idx]
      byte_in_seg = cursor_byte - seg_offset
      [display_row + seg_idx, display_column(seg_text, byte_in_seg)]
    end

    def render_tabline
      tabs = @editor.tabs
      return '' if tabs.size < 2

      parts = tabs.each_with_index.map do |tab, i|
        label = " #{i + 1}: #{tab.display_name} "
        if i == @editor.current_tab_index
          REVERSE_ON + label + REVERSE_OFF
        else
          DIM_ON + label + DIM_OFF
        end
      end
      tabline = parts.join('|')
      move_to(1, 1) + ERASE_LINE + truncate(tabline, @cols + 200)
    end

    def list_overlay_rows
      [(@rows / 2).to_i, 4].max
    end

    def render_listing_overlay
      view = @editor.list_view
      return '' unless view

      out = +''
      rows = list_overlay_rows
      content_rows = rows - 1
      page = view.page(rows)
      start_row = @rows - rows
      content_rows.times do |i|
        line = page[i] || ''
        out << move_to(start_row + i, 1) << ERASE_LINE << truncate(line, @cols)
      end
      out
    end

    attr_reader :rows

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
      offset = @editor.settings.get(:scrolloff).to_i.clamp(0, [visible / 2 - 1, 0].max)
      if cursor_line < win.scroll_top + offset
        win.scroll_top = [cursor_line - offset, 0].max
      elsif cursor_line >= win.scroll_top + visible - offset
        win.scroll_top = cursor_line - visible + offset + 1
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
        apply_syntax_highlight(line, width)
      end
    end

    def apply_syntax_highlight(line, width)
      lang = current_language
      return truncate(line, width) unless lang

      segments = Rvim::Syntax.highlight(line, lang)
      return truncate(line, width) if segments.empty?

      out = line.dup
      segments.sort_by { |s, _e, _c| -s }.each do |s, e, color|
        head = out.byteslice(0, s) || +''
        mid = out.byteslice(s, e - s + 1) || +''
        tail = out.byteslice(e + 1, out.bytesize - e - 1) || +''
        out = head + Rvim::Syntax::COLORS[color] + mid + Rvim::Syntax::RESET + tail
      end
      truncate(out, width + segments.size * (Rvim::Syntax::COLORS[:default].bytesize + Rvim::Syntax::RESET.bytesize))
    end

    def current_language
      buf = @editor.current_window&.buffer
      return nil unless buf

      setting = @editor.settings.get(:syntax)
      case setting
      when :off, false then nil
      when :auto, true then Rvim::Syntax.detect_language(buf.filepath)
      when Symbol then setting
      when String then setting.to_sym
      end
    end

    def render_line(line)
      ts = @editor.settings.get(:tabstop) || 8
      ts = 8 if ts <= 0
      list_on = @editor.settings.get(:list)
      out = line.to_s.gsub("\t", list_on ? render_tab_marker(ts) : (' ' * ts))
      out = mark_trailing_whitespace(out) if list_on
      out
    end

    TAB_MARKER_HEAD = '>'
    TAB_MARKER_FILL = '-'
    TRAIL_MARKER = '·'

    def render_tab_marker(width)
      return TAB_MARKER_HEAD if width <= 1

      TAB_MARKER_HEAD + (TAB_MARKER_FILL * (width - 1))
    end

    def mark_trailing_whitespace(str)
      str.sub(/[ ]+\z/) { |trail| TRAIL_MARKER * trail.length }
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
      ruler = if @editor.settings.get(:ruler)
                total = (is_current ? @editor.buffer_of_lines : buffer.lines).size
                ln = (is_current ? @editor.line_index : buffer.line_index) + 1
                col = (is_current ? @editor.byte_pointer : buffer.byte_pointer) + 1
                pct = total.zero? ? 0 : (ln * 100 / total)
                "    #{ln},#{col}    #{pct}%"
              else
                ''
              end
      " #{mode} #{name}#{modified}#{ruler}#{recording}".lstrip.then { |s| " #{s}" }
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
      when :listing
        view = @editor.list_view
        view && view.more?(list_overlay_rows) ? '-- More --' : 'Press ENTER or type command to continue'
      else
        @editor.status_message ? @editor.status_message.to_s : ''
      end
    end

    def display_column(line, byte_pointer)
      Reline::Unicode.calculate_width(line.byteslice(0, byte_pointer) || '')
    end

    def truncate(str, width)
      # Char-count truncation. Used by ANSI-splice helpers that compute their
      # own inflated widths to account for escape bytes. New code should prefer
      # truncate_to_width for pure text.
      return str if str.length <= width

      str[0, width]
    end

    # Display-width-aware truncation. Walks chars, summing Reline::Unicode
    # widths, and stops when the next char would overflow.
    def truncate_to_width(str, width)
      take_display_width(str, 0, width)
    end

    # Display-width-aware padding to exactly `width` cells. Truncates if too
    # wide, pads with spaces if too narrow.
    def pad_to_width(str, width)
      out = truncate_to_width(str, width)
      current = Reline::Unicode.calculate_width(out)
      out + (' ' * (width - current))
    end

    # For rendered strings that may contain ANSI escape sequences (highlights):
    # pad with spaces so the visible content reaches `width`. Doesn't try to
    # truncate (caller already did that with the right ANSI-aware budget).
    def pad_render_to_width(str, width)
      visible = visible_width(str)
      str + (' ' * [width - visible, 0].max)
    end

    # Display width of a string ignoring ANSI escape sequences.
    def visible_width(str)
      no_ansi = str.gsub(/\e\[[\d;]*[a-zA-Z]/, '')
      Reline::Unicode.calculate_width(no_ansi)
    end

    def move_to(row, col)
      "\e[#{row};#{col}H"
    end
  end
end
