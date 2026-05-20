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

    # DECSCUSR cursor shapes — match NeoVim's default 'guicursor' for
    # n: block, i/c: vertical bar, r: underline.
    CURSOR_BLOCK = "\e[2 q"
    CURSOR_BAR = "\e[6 q"
    CURSOR_UNDERLINE = "\e[4 q"

    def initialize(editor)
      @editor = editor
      @rows = 24
      @cols = 80
    end

    # Wrap `text` in the SGR open/close pair from the named highlight
    # group. Falls back to the unstyled text when the group isn't
    # registered (shouldn't happen for the chrome defaults, but
    # keeps the renderer resilient if a plugin clears the registry).
    def hl(name, text)
      pair = @editor.hl_groups.lookup(name)
      return text.to_s unless pair && (!pair.open.empty? || !pair.close.empty?)

      "#{pair.open}#{text}#{pair.close}"
    end

    def scroll_top
      @editor.current_window&.scroll_top || 0
    end

    def scroll_top=(value)
      @editor.current_window.scroll_top = value if @editor.current_window
    end

    MOUSE_ENABLE = "\e[?1000h\e[?1006h"
    MOUSE_DISABLE = "\e[?1006l\e[?1000l"

    def setup
      $stdout.write(SMCUP)
      $stdout.write(CLEAR)
      $stdout.write(HOME)
      enable_mouse if mouse_enabled?
      $stdout.flush
    end

    def teardown
      disable_mouse
      $stdout.write(CURSOR_BLOCK)
      $stdout.write(SHOW_CURSOR)
      $stdout.write(RMCUP)
      $stdout.flush
    end

    def mouse_enabled?
      !@editor.settings.get(:mouse).to_s.empty?
    end

    def enable_mouse
      $stdout.write(MOUSE_ENABLE)
    end

    def disable_mouse
      $stdout.write(MOUSE_DISABLE)
    end

    def gutter_width_for(buffer)
      gutter_width(buffer)
    end

    def tabline_height
      stal = @editor.settings.get(:showtabline).to_i
      return 0 if stal <= 0
      return 1 if stal >= 2
      # stal == 1: only when more than one tab
      @editor.tabs.size > 1 ? 1 : 0
    end

    def render_title
      str = @editor.settings.get(:titlestring).to_s
      title = if str.empty?
                name = @editor.filepath ? File.basename(@editor.filepath) : '[No Name]'
                "#{name} - rvim"
              else
                str
              end
      "\e]0;#{title}\a"
    end

    def render
      @rows, @cols = Reline::IOGate.get_screen_size
      reserved = @editor.prompt_mode == :listing ? list_overlay_rows + 1 : 1
      reserved_top = tabline_height
      layout_windows(@rows - reserved - reserved_top, @cols)
      if reserved_top.positive?
        @editor.windows.each { |w| w.row += reserved_top }
      end

      out = +HIDE_CURSOR
      out << render_title if @editor.settings.get(:title)
      out << render_tabline if reserved_top.positive?
      @editor.windows.each { |win| out << render_window(win) }
      out << render_vertical_dividers
      # Floating windows render AFTER tiled ones so they overlay on
      # top. Sorted by zindex (low → high) so higher-z floats end up
      # last and appear topmost.
      sorted_floats = @editor.floating_windows.reject(&:hide).sort_by(&:zindex)
      sorted_floats.each { |fw| out << render_floating_window(fw) }
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
      elsif cw && cw.floating?
        # Floating windows have no gutter; cursor offsets are relative
        # to the inside of the border (if any).
        pad = (cw.border && cw.border != :none) ? 1 : 0
        line = @editor.buffer_of_lines[@editor.line_index] || ''
        col = display_column(line, @editor.byte_pointer)
        cursor_row = cw.row + pad + (@editor.line_index - (cw.scroll_top || 0)) + 1
        cursor_col = cw.col + pad + col + 1
        out << move_to(cursor_row, cursor_col)
      elsif cw
        gw = gutter_width(cw.buffer)
        content_width = cw.width - gw
        wrap_on = @editor.settings.get(:wrap)
        display_row_offset, display_col = cursor_display_position(cw, content_width, wrap_on)
        cursor_row = cw.row + display_row_offset + 1
        cursor_col = cw.col + gw + display_col + 1
        out << move_to(cursor_row, cursor_col)
      end
      out << cursor_shape_for_mode
      out << SHOW_CURSOR

      $stdout.write(out)
      $stdout.flush
    end

    def cursor_shape_for_mode
      if @editor.respond_to?(:replace_mode) && @editor.replace_mode
        CURSOR_UNDERLINE
      elsif @editor.prompt_mode || @editor.editing_mode_label == :vi_insert
        CURSOR_BAR
      else
        CURSOR_BLOCK
      end
    end

    def content_width_for(win)
      return 0 unless win

      gw = gutter_width(win.buffer)
      [win.width - gw, 0].max
    end

    def split_segments_public(line, max_width)
      split_line_segments(line, max_width)
    end

    # Editor#list_rows reads this when computing how many rows the listing
    # overlay reserves at the bottom of the screen, so it must be public.
    def list_overlay_rows
      [(@rows / 2).to_i, 4].max
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
      sign_w = sign_column_width_for(buffer)
      lsp_signs = lsp_signs_for(buffer)
      lsp_ranges = lsp_ranges_for(buffer)
      lsp_hints = lsp_inlay_hints_for(buffer)
      lsp_dhl = lsp_document_highlights_for(buffer)
      lsp_tokens = lsp_semantic_tokens_for(buffer)
      content_width = win.width - gw
      cursor_idx = is_current ? @editor.line_index : buffer.line_index
      wrap_on = @editor.settings.get(:wrap)

      display_rows = build_display_rows(buffer, win.scroll_top, content_rows, content_width, wrap_on, lsp_ranges)

      cursorline_on = @editor.settings.get(:cursorline)
      sbr = @editor.settings.get(:showbreak).to_s
      out = +''
      display_rows.each_with_index do |row, i|
        line_idx, byte_off, segment, is_fold = row
        if line_idx.nil?
          gutter = ' ' * gw
          rendered = hl('EndOfBuffer', '~')
        elsif is_fold
          gutter = gutter_text(line_idx, cursor_idx, buffer.lines.size, gw, true, sign_w: sign_w)
          rendered = truncate_to_width(segment, content_width)
        else
          line_sign = lsp_signs[line_idx]
          gutter = byte_off.zero? ? gutter_text(line_idx, cursor_idx, buffer.lines.size, gw, true, sign: line_sign, sign_w: sign_w) : (' ' * gw)
          line_diags = lsp_ranges[line_idx]
          full_line = render_line(buffer.lines[line_idx])
          rendered = if is_current
                       apply_current_highlights_segment(full_line, line_idx, byte_off, segment, content_width)
                     else
                       truncate_to_width(segment, content_width)
                     end
          # Document highlights (matches of the symbol under cursor)
          # paint a subtle background. Goes BEFORE diagnostics so the
          # diagnostic underline color wins over the highlight bg on
          # overlapping ranges.
          # Semantic tokens (server-driven syntax highlighting). Goes
          # FIRST so subsequent overlays (doc highlight bg, diagnostic
          # underline) wrap around our colored spans. Each token is
          # painted with a distinct fg color; the rendered line still
          # gets the regex highlighter's colors where semanticTokens
          # didn't cover (ruby-lsp is conservative).
          line_tokens = lsp_tokens[line_idx]
          if line_tokens && !line_tokens.empty? && byte_off.zero?
            rendered = apply_semantic_tokens_overlay(rendered, line_tokens, buffer.lines[line_idx].to_s)
          end
          # Extmarks: plugin-driven highlight spans. Sit between
          # semantic-token coloring and doc-highlight/diagnostic
          # overlays so plugin colors compose with both. Sorted by
          # priority ascending (later spans cover earlier ones).
          if byte_off.zero?
            marks = extmarks_intersecting(buffer, line_idx)
            rendered = apply_extmark_overlay(rendered, marks, buffer.lines[line_idx].to_s) unless marks.empty?
          end
          line_dhl = lsp_dhl[line_idx]
          if line_dhl && !line_dhl.empty? && byte_off.zero?
            rendered = apply_document_highlight_overlay(rendered, line_dhl, buffer.lines[line_idx].to_s)
          end
          # Diagnostic underline goes LAST. Earlier passes (syntax,
          # search, selection) tokenize the line text and would splice
          # color SGR mid-sequence if our underline SGR were already
          # embedded — applying it here wraps the post-highlight output.
          if line_diags && !line_diags.empty? && byte_off.zero?
            rendered = apply_diagnostic_overlay(rendered, line_diags)
          end
          # Inlay hints: splice ghost-text labels at their reported
          # character positions, skipping the cursor line so the
          # cursor's display column stays in sync with buffer bytes.
          line_hints = lsp_hints[line_idx]
          if line_hints && !line_hints.empty? && byte_off.zero? && line_idx != cursor_idx
            rendered = apply_inlay_hints_overlay(rendered, line_hints)
          end
          if !sbr.empty? && byte_off.is_a?(Integer) && byte_off > 0
            rendered = truncate_to_width(sbr + rendered, content_width)
          end
          if @editor.settings.get(:breakindent) && byte_off.is_a?(Integer) && byte_off > 0
            indent = (buffer.lines[line_idx] || '')[/\A[ \t]*/].to_s
            rendered = truncate_to_width(indent + rendered, content_width) if indent && !indent.empty?
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

      ls = @editor.settings.get(:laststatus).to_i
      show_status = ls >= 2 || (ls == 1 && @editor.windows.size > 1)
      if show_status
        # Per-window status row at the bottom of the window. Active
        # window uses StatusLine; the others use StatusLineNC.
        out << move_to(win.row + win.height, win.col + 1)
        text = pad_to_width(truncate_to_width(window_status(win, is_current), win.width), win.width)
        out << hl(is_current ? 'StatusLine' : 'StatusLineNC', text)
      end

      if is_current && @editor.completion_popup && !@editor.completion_popup.empty?
        out << render_completion_popup(win, gw, content_width, wrap_on)
      end

      if is_current && @editor.completion_detail_popup && !@editor.completion_detail_popup.empty?
        out << render_completion_detail_popup(win, gw, content_width, wrap_on)
      end

      if is_current && @editor.hover_popup && !@editor.hover_popup.empty?
        out << render_hover_popup(win, gw, content_width, wrap_on)
      end

      if is_current && @editor.signature_popup && !@editor.signature_popup.empty?
        out << render_signature_popup(win, gw, content_width, wrap_on)
      end

      if is_current && @editor.diagnostic_popup && !@editor.diagnostic_popup.empty?
        out << render_diagnostic_popup(win, gw, content_width, wrap_on)
      end

      cc_cols = parse_colorcolumns(@editor.settings.get(:colorcolumn))
      unless cc_cols.empty?
        out << render_colorcolumn_overlay(win, gw, content_width, cc_cols, display_rows.size)
      end

      if is_current && @editor.settings.get(:cursorcolumn)
        out << render_cursorcolumn_overlay(win, gw, content_width, wrap_on, display_rows.size)
      end
      out
    end

    def render_cursorcolumn_overlay(win, gw, content_width, wrap_on, rows_drawn)
      _, cursor_col = cursor_display_position(win, content_width, wrap_on)
      return '' if cursor_col < 0 || cursor_col >= content_width

      out = +''
      cc_prefix = Rvim::Highlights.ansi_prefix('CursorColumn')
      cc_suffix = Rvim::Highlights.ansi_suffix('CursorColumn')
      screen_col = win.col + gw + cursor_col + 1
      rows_drawn.times do |i|
        out << move_to(win.row + i + 1, screen_col)
        out << cc_prefix << ' ' << cc_suffix
      end
      out
    end

    def parse_colorcolumns(spec)
      spec.to_s.split(',').map do |t|
        t = t.strip
        next nil if t.empty?

        t.to_i
      end.compact.select { |n| n > 0 }
    end

    def render_colorcolumn_overlay(win, gw, content_width, cols, rows_drawn)
      out = +''
      cc_prefix = Rvim::Highlights.ansi_prefix('ColorColumn')
      cc_suffix = Rvim::Highlights.ansi_suffix('ColorColumn')
      cols.each do |col|
        next if col > content_width
        next if col <= 0

        screen_col = win.col + gw + col
        rows_drawn.times do |i|
          out << move_to(win.row + i + 1, screen_col)
          out << cc_prefix << ' ' << cc_suffix
        end
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

    # Box-drawing glyphs per border style. `chars` is
    # [top_left, top, top_right, right, bottom_right, bottom,
    #  bottom_left, left]. :solid uses the same glyph for every
    # corner+edge so any monospace font shows a filled rectangle;
    # :rounded uses the curved corners.
    FLOAT_BORDER_GLYPHS = {
      single: %w[┌ ─ ┐ │ ┘ ─ └ │].freeze,
      double: %w[╔ ═ ╗ ║ ╝ ═ ╚ ║].freeze,
      rounded: %w[╭ ─ ╮ │ ╯ ─ ╰ │].freeze,
      solid: ['▛', '▀', '▜', '▐', '▟', '▄', '▙', '▌'].freeze,
    }.freeze

    # Render one floating window: border + content. The window's
    # `row`/`col` are absolute screen coords. With a border the
    # content area shrinks by 2 in each dim; without a border the
    # content fills the entire frame.
    def render_floating_window(win)
      buf = win.buffer
      return '' if buf.nil?

      has_border = !win.border.nil? && win.border != :none
      pad = has_border ? 1 : 0
      content_top  = win.row + pad
      content_left = win.col + pad
      content_rows = [win.height - (pad * 2), 0].max
      content_width = [win.width - (pad * 2), 0].max

      out = +''
      out << render_float_border(win) if has_border
      content_rows.times do |i|
        line_idx = (win.scroll_top || 0) + i
        raw = buf.lines[line_idx]
        text = raw.nil? ? '' : raw.to_s
        # Reuse the syntax highlighter for file-backed buffers; for
        # scratch buffers (no syntax detected) it falls through to
        # plain text via the truncate fast-path.
        highlighted = apply_syntax_highlight(text, content_width)
        rendered = pad_render_to_width(highlighted, content_width)
        out << move_to(content_top + i + 1, content_left + 1)
        out << rendered
      end
      out
    end

    private def render_float_border(win)
      glyphs = FLOAT_BORDER_GLYPHS[win.border] || FLOAT_BORDER_GLYPHS[:single]
      tl, t, tr, r, br, b, bl, l = glyphs
      out = +''
      inner_w = [win.width - 2, 0].max
      # Top edge — splice in title centred if present.
      top = +(tl) << t * inner_w << tr
      if win.title && !win.title.empty?
        label = " #{win.title} "
        max = inner_w
        label = truncate_to_width(label, max)
        start = 1 + ((inner_w - visible_width(label)) / 2)
        top = top.dup
        # Walk char-by-char; replace inside the top-edge segment.
        rebuilt = +(tl)
        rebuilt << label
        rebuilt << t * [inner_w - visible_width(label), 0].max
        rebuilt << tr
        top = rebuilt
      end
      out << move_to(win.row + 1, win.col + 1) << top
      # Side edges row-by-row.
      (win.height - 2).times do |i|
        out << move_to(win.row + 1 + i + 1, win.col + 1) << l
        out << move_to(win.row + 1 + i + 1, win.col + win.width) << r
      end
      # Bottom edge — footer centred if present.
      bottom = +(bl) << b * inner_w << br
      if win.footer && !win.footer.empty?
        label = " #{win.footer} "
        label = truncate_to_width(label, inner_w)
        rebuilt = +(bl)
        rebuilt << label
        rebuilt << b * [inner_w - visible_width(label), 0].max
        rebuilt << br
        bottom = rebuilt
      end
      out << move_to(win.row + win.height, win.col + 1) << bottom
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

    # Side-panel that sits to the RIGHT of the main completion
    # popup, showing detail + documentation for the selected
    # candidate. Falls back to the LEFT side if there's no room
    # right; falls back to below if neither side fits.
    def render_completion_detail_popup(win, gw, content_width, wrap_on)
      popup = @editor.completion_detail_popup
      main = @editor.completion_popup
      return '' if popup.nil? || popup.empty? || main.nil?

      cursor_row, _cursor_col = cursor_display_position(win, content_width, wrap_on)
      base_byte = @editor.completion_base_byte || 0
      cursor_line = @editor.line_index
      buffer = win.buffer
      line_text = render_line(buffer.lines[cursor_line] || '')
      base_col = display_column(line_text, base_byte)

      width = popup.width
      visible = popup.visible_height
      need_bar = popup.needs_scrollbar?
      total_width = width + (need_bar ? 1 : 0)

      # Main popup occupies [base_col, base_col + main.width). Try to
      # sit immediately to its right.
      main_total = main.width + (main.needs_scrollbar? ? 1 : 0)
      right_anchor = win.col + gw + base_col + 1 + main_total
      max_col = win.col + win.width
      start_col = if right_anchor + total_width <= max_col + 1
                    right_anchor
                  else
                    # Right doesn't fit — try left of the main popup.
                    left = win.col + gw + base_col + 1 - total_width
                    [left, win.col + 1].max
                  end

      base_row = win.row + cursor_row + 1
      base_row = (win.row + cursor_row - visible).clamp(win.row, win.row + win.height - 1) \
        if base_row + visible > win.row + win.height - 1

      out = +''
      popup.visible_range.each_with_index do |idx, i|
        line = pad_to_width(truncate_to_width(popup.contents[idx].to_s, width), width)
        line_with_bar = line + (need_bar ? scrollbar_glyph_for(popup, idx) : '')
        out << move_to(base_row + i + 1, start_col)
        out << DIM_ON << line_with_bar << DIM_OFF
      end
      out
    end

    # LSP hover popup. Anchored at the cursor row + 1 (below the
    # cursor); flips above when it'd overflow the bottom. Width and
    # height clamped via the popup's max_width/max_height. Mirrors
    # render_completion_popup but anchors at the cursor column rather
    # than the completion base.
    def render_hover_popup(win, gw, content_width, wrap_on)
      popup = @editor.hover_popup
      cursor_row, cursor_col = cursor_display_position(win, content_width, wrap_on)

      width = popup.width
      visible = popup.visible_height
      need_bar = popup.needs_scrollbar?
      total_width = width + (need_bar ? 1 : 0)

      base_row = win.row + cursor_row + 1
      if base_row + visible > win.row + win.height - 1
        base_row = (win.row + cursor_row - visible).clamp(win.row, win.row + win.height - 1)
      end
      start_col = win.col + gw + cursor_col + 1
      max_col = win.col + win.width
      start_col = [start_col, max_col - total_width + 1].min
      start_col = [start_col, win.col + 1].max

      out = +''
      popup.visible_range.each_with_index do |idx, i|
        line = pad_to_width(truncate_to_width(popup.contents[idx].to_s, width), width)
        line_with_bar = line + (need_bar ? scrollbar_glyph_for(popup, idx) : '')
        out << move_to(base_row + i + 1, start_col)
        out << REVERSE_ON << line_with_bar << REVERSE_OFF
      end
      out
    end

    # Same placement template as render_hover_popup. The diagnostic
    # popup auto-opens when the cursor sits on a diagnostic range, so
    # we keep it close to the cursor (below by default, above on
    # overflow) for fast visual association.
    def render_diagnostic_popup(win, gw, content_width, wrap_on)
      popup = @editor.diagnostic_popup
      cursor_row, cursor_col = cursor_display_position(win, content_width, wrap_on)

      width = popup.width
      visible = popup.visible_height
      need_bar = popup.needs_scrollbar?
      total_width = width + (need_bar ? 1 : 0)

      base_row = win.row + cursor_row + 1
      if base_row + visible > win.row + win.height - 1
        base_row = (win.row + cursor_row - visible).clamp(win.row, win.row + win.height - 1)
      end
      start_col = win.col + gw + cursor_col + 1
      max_col = win.col + win.width
      start_col = [start_col, max_col - total_width + 1].min
      start_col = [start_col, win.col + 1].max

      out = +''
      popup.visible_range.each_with_index do |idx, i|
        line = pad_to_width(truncate_to_width(popup.contents[idx].to_s, width), width)
        line_with_bar = line + (need_bar ? scrollbar_glyph_for(popup, idx) : '')
        out << move_to(base_row + i + 1, start_col)
        out << REVERSE_ON << line_with_bar << REVERSE_OFF
      end
      out
    end

    # Identical placement strategy to render_hover_popup but anchors
    # ABOVE the cursor by default (signature popup is most useful when
    # it doesn't cover the args you're typing).
    def render_signature_popup(win, gw, content_width, wrap_on)
      popup = @editor.signature_popup
      cursor_row, cursor_col = cursor_display_position(win, content_width, wrap_on)

      width = popup.width
      visible = popup.visible_height
      need_bar = popup.needs_scrollbar?
      total_width = width + (need_bar ? 1 : 0)

      base_row = win.row + cursor_row - visible
      base_row = win.row + cursor_row + 1 if base_row < win.row
      start_col = win.col + gw + cursor_col + 1
      max_col = win.col + win.width
      start_col = [start_col, max_col - total_width + 1].min
      start_col = [start_col, win.col + 1].max

      out = +''
      popup.visible_range.each_with_index do |idx, i|
        line = pad_to_width(truncate_to_width(popup.contents[idx].to_s, width), width)
        line_with_bar = line + (need_bar ? scrollbar_glyph_for(popup, idx) : '')
        out << move_to(base_row + i + 1, start_col)
        out << REVERSE_ON << line_with_bar << REVERSE_OFF
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
    def build_display_rows(buffer, scroll_top, content_rows, content_width, wrap_on, _lsp_ranges = {})
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

      linebreak = @editor.settings.get(:linebreak)
      segments = []
      offset = 0
      total = line.bytesize
      while offset < total
        seg = take_display_width(line, offset, max_width)
        bytes = seg.bytesize
        if bytes.zero?
          ch = line.byteslice(offset, total - offset).each_char.first || ''
          bytes = ch.bytesize
          seg = ch
        elsif linebreak && offset + bytes < total && !line.byteslice(offset + bytes, 1).match?(/\s/)
          # We're about to split mid-word. Try to back up to the last whitespace
          # within the segment so the break aligns to a word boundary.
          last_ws = seg.rindex(/\s/)
          if last_ws && last_ws.positive?
            # Slice up to and including the whitespace
            new_bytes = seg.byteslice(0, last_ws + 1).bytesize
            seg = seg.byteslice(0, last_ws + 1)
            bytes = new_bytes
          end
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
        hl(i == @editor.current_tab_index ? 'TabLineSel' : 'TabLine', label)
      end
      sep = hl('TabLine', '|')
      tabline = parts.join(sep)
      move_to(1, 1) + ERASE_LINE + truncate(tabline, @cols + 200)
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
      bar = hl('WinSeparator', '│')
      @editor.windows[0..-2].each do |win|
        col = win.col + win.width + 1
        win.height.times do |i|
          out << move_to(win.row + i + 1, col) << bar
        end
      end
      out
    end

    def gutter_width(buffer)
      width = 0
      if @editor.settings.get(:number) || @editor.settings.get(:relativenumber)
        configured = @editor.settings.get(:numberwidth).to_i
        configured = 4 if configured <= 0
        digits = Math.log10([buffer.lines.size, 1].max).floor + 1
        width = [digits + 1, configured].max
        width = width.clamp(2, 12)
      end
      width += sign_column_width_for(buffer)
      width
    end

    def sign_column_width_for(buffer)
      case @editor.settings.get(:signcolumn).to_s
      when 'yes' then 2
      when 'number'
        # signs displayed in the number column — no extra space
        0
      when 'auto'
        lsp_signs_for(buffer).any? ? 2 : 0
      else 0 # 'no' — never show
      end
    end

    # Shim for older callers (and tests) that don't have a buffer in hand.
    # Returns 0 for 'auto' since we can't check diagnostics without a buffer;
    # render-path code uses sign_column_width_for(buffer) instead.
    def sign_column_width
      case @editor.settings.get(:signcolumn).to_s
      when 'yes' then 2
      else 0
      end
    end

    # 0-based line => severity (1..4) for the buffer, or {} when LSP is off.
    def lsp_signs_for(buffer)
      return {} unless buffer
      return {} unless @editor.respond_to?(:settings) && @editor.settings.get(:lsp_enabled)
      return {} unless @editor.respond_to?(:lsp) && @editor.lsp.respond_to?(:diagnostic_signs)

      @editor.lsp.diagnostic_signs(buffer)
    end

    # 0-based line => [{first_col, last_col, severity}, ...] for the buffer.
    def lsp_ranges_for(buffer)
      return {} unless buffer
      return {} unless @editor.respond_to?(:settings) && @editor.settings.get(:lsp_enabled)
      return {} unless @editor.respond_to?(:lsp) && @editor.lsp.respond_to?(:diagnostic_ranges)

      @editor.lsp.diagnostic_ranges(buffer)
    end

    # 0-based line => InlayHint[] for the buffer, or {} when LSP is off.
    def lsp_inlay_hints_for(buffer)
      return {} unless buffer
      return {} unless @editor.respond_to?(:settings) && @editor.settings.get(:lsp_enabled)
      return {} unless @editor.respond_to?(:lsp) && @editor.lsp.respond_to?(:inlay_hints_by_line)

      @editor.lsp.inlay_hints_by_line(buffer)
    end

    # 0-based line => decoded SemanticToken[] for the buffer, or {}
    # when LSP is off / server doesn't support semanticTokens.
    def lsp_semantic_tokens_for(buffer)
      return {} unless buffer
      return {} unless @editor.respond_to?(:settings) && @editor.settings.get(:lsp_enabled)
      return {} unless @editor.respond_to?(:lsp) && @editor.lsp.respond_to?(:semantic_tokens_by_line)

      @editor.lsp.semantic_tokens_by_line(buffer)
    end

    # 0-based line => DocumentHighlight[] for the buffer (cursor-symbol
    # occurrences), or {} when LSP is off.
    def lsp_document_highlights_for(buffer)
      return {} unless buffer
      return {} unless @editor.respond_to?(:settings) && @editor.settings.get(:lsp_enabled)
      return {} unless @editor.respond_to?(:lsp) && @editor.lsp.respond_to?(:document_highlights_by_line)

      @editor.lsp.document_highlights_by_line(buffer)
    end

    SEVERITY_GLYPHS = { 1 => 'E', 2 => 'W', 3 => 'I', 4 => 'H' }.freeze
    SEVERITY_COLORS = { 1 => 196, 2 => 214, 3 => 75, 4 => 245 }.freeze

    def severity_glyph(severity)
      SEVERITY_GLYPHS[severity] || '*'
    end

    def severity_color(severity)
      SEVERITY_COLORS[severity] || 245
    end

    def gutter_text(idx, cursor_idx, total, gw, has_line, sign: nil, sign_w: 0)
      return '' if gw.zero?

      number = if !has_line
                 ''
               elsif @editor.settings.get(:relativenumber) && idx != cursor_idx
                 (idx - cursor_idx).abs.to_s
               else
                 (idx + 1).to_s
               end

      number_w = gw - sign_w
      sign_cell = if sign_w.zero?
                    ''
                  elsif sign
                    color = severity_color(sign)
                    "\e[38;5;#{color}m#{severity_glyph(sign)} \e[39m"
                  else
                    ' ' * sign_w
                  end
      if number_w <= 0
        sign_cell
      else
        # Colorscheme can customize LineNr / CursorLineNr; default
        # mirrors the historical `DIM_ON ... DIM_OFF` look.
        group = (idx == cursor_idx) ? 'CursorLineNr' : 'LineNr'
        hl(group, number.rjust(number_w - 1) + ' ') + sign_cell
      end
    end

    def adjust_window_scroll(win, visible)
      buffer = win.buffer
      cursor_line = (win == @editor.current_window) ? @editor.line_index : buffer.line_index
      offset = @editor.settings.get(:scrolloff).to_i.clamp(0, [visible / 2 - 1, 0].max)
      jump = [@editor.settings.get(:scrolljump).to_i, 1].max
      old_top = win.scroll_top

      if cursor_line < win.scroll_top + offset
        target = [cursor_line - offset, 0].max
        # If a scroll is happening, ensure we move at least `jump` lines.
        if old_top - target < jump && target < old_top
          target = [old_top - jump, 0].max
        end
        win.scroll_top = target
      elsif cursor_line >= win.scroll_top + visible - offset
        target = cursor_line - visible + offset + 1
        if target - old_top < jump && target > old_top
          target = old_top + jump
        end
        # But don't scroll past where the cursor would still be off screen
        target = [target, cursor_line - visible + offset + 1].max
        win.scroll_top = target
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
      added_bytes = 0
      segments.sort_by { |s, _e, _c| -s }.each do |s, e, group|
        head = out.byteslice(0, s) || +''
        mid = out.byteslice(s, e - s + 1) || +''
        tail = out.byteslice(e + 1, out.bytesize - e - 1) || +''
        prefix, suffix = syntax_sgr_for(group)
        out = head + prefix + mid + suffix + tail
        added_bytes += prefix.bytesize + suffix.bytesize
      end
      truncate(out, width + added_bytes)
    end

    # Syntax categories ("Constant", "String", etc.) used to resolve
    # only through Rvim::Highlights (the legacy 16-color registry).
    # That left colorscheme plugins like tokyonight without any way
    # to recolor syntax — nvim_set_hl writes to editor.hl_groups,
    # which the syntax painter never consulted.
    #
    # Prefer the plugin-facing registry first; fall back to the
    # legacy one for groups the colorscheme hasn't touched.
    def syntax_sgr_for(group)
      name = group.to_s
      pair = @editor.hl_groups.lookup(name)
      if pair && (!pair.open.empty? || !pair.close.empty?)
        return [pair.open, pair.close]
      end

      [Rvim::Highlights.ansi_prefix(name), Rvim::Highlights.ansi_suffix(name)]
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

    SPELL_ERR_ON = "\e[31m"
    SPELL_ERR_OFF = "\e[39m"

    def render_line(line)
      ts = @editor.settings.get(:tabstop) || 8
      ts = 8 if ts <= 0
      list_on = @editor.settings.get(:list)
      lcs = list_on ? parse_listchars(@editor.settings.get(:listchars)) : nil

      out = line.to_s.gsub("\t", list_on ? render_tab_marker(lcs['tab'] || '> ', ts) : (' ' * ts))
      out = mark_trailing_whitespace(out, lcs['trail']) if list_on && lcs['trail']
      out = apply_spell_highlight(out) if @editor.settings.get(:spell)
      out
    end

    def apply_spell_highlight(line)
      line.gsub(/[A-Za-z]+/) do |word|
        Rvim::Spell.misspelled?(word) ? "#{SPELL_ERR_ON}#{word}#{SPELL_ERR_OFF}" : word
      end
    end

    # Wrap each byte range in `ranges` with diagnostic underline SGR,
    # walking the post-highlighted `rendered` string and skipping past
    # any existing SGR escape sequences when counting buffer-line bytes.
    # `ranges` first_col/last_col refer to the ORIGINAL buffer line's
    # bytes (not the rendered string with embedded escapes), so we sync
    # the two cursors as we walk. Multi-byte chars are emitted whole, so
    # the SGR boundaries always land on a UTF-8 char start.
    DIAG_SGR_RE = /\A\e\[[\d;]*[a-zA-Z]/.freeze

    def apply_diagnostic_overlay(rendered, ranges)
      return rendered if ranges.nil? || ranges.empty?

      sorted = ranges.sort_by { |r| r[:first_col].to_i }
      out = +''
      pos = 0
      orig = 0
      idx = 0
      active = nil
      total = rendered.bytesize

      while pos < total
        if rendered.getbyte(pos) == 0x1b && (m = rendered.byteslice(pos..-1)&.match(DIAG_SGR_RE))
          out << m[0]
          pos += m[0].bytesize
          next
        end

        if active && orig >= active[:last_col].to_i
          out << "\e[24;39m"
          active = nil
          idx += 1
        end

        if active.nil? && idx < sorted.size && orig >= sorted[idx][:first_col].to_i
          active = sorted[idx]
          out << "\e[4;38;5;#{severity_color(active[:severity])}m"
        end

        cb = rendered.getbyte(pos)
        char_bytes = if cb.nil? || cb < 0x80 then 1
                     elsif cb < 0xc0 then 1
                     elsif cb < 0xe0 then 2
                     elsif cb < 0xf0 then 3
                     else 4
                     end
        out << rendered.byteslice(pos, char_bytes)
        pos += char_bytes
        orig += char_bytes
      end

      out << "\e[24;39m" if active
      out
    end

    # Splice ghost-text inlay-hint labels into an already-rendered
    # line. Same SGR-aware walk as apply_diagnostic_overlay: step
    # through bytes while counting original buffer chars, and when
    # the next hint's `position.character` matches the cursor, emit
    # its label wrapped in the ghost-text SGR (italic + muted gray)
    # plus optional paddingLeft/paddingRight spaces. The cursor line
    # is skipped by the caller so this never widens the column the
    # cursor is on.
    def apply_inlay_hints_overlay(rendered, hints)
      return rendered if hints.nil? || hints.empty?

      sorted = hints.sort_by { |h| h.dig(:position, :character).to_i }
      out = +''
      pos = 0
      orig = 0
      hint_idx = 0
      total = rendered.bytesize

      while pos < total
        if rendered.getbyte(pos) == 0x1b && (m = rendered.byteslice(pos..-1)&.match(DIAG_SGR_RE))
          out << m[0]
          pos += m[0].bytesize
          next
        end

        while hint_idx < sorted.size && sorted[hint_idx].dig(:position, :character).to_i == orig
          out << format_inlay_hint(sorted[hint_idx])
          hint_idx += 1
        end

        cb = rendered.getbyte(pos)
        char_bytes = if cb.nil? || cb < 0x80 then 1
                     elsif cb < 0xc0 then 1
                     elsif cb < 0xe0 then 2
                     elsif cb < 0xf0 then 3
                     else 4
                     end
        out << rendered.byteslice(pos, char_bytes)
        pos += char_bytes
        orig += 1
      end

      # Hints anchored past the rendered end of line trail at the
      # end (e.g. a type hint on an empty line).
      while hint_idx < sorted.size
        out << format_inlay_hint(sorted[hint_idx])
        hint_idx += 1
      end
      out
    end

    # InlayHint.label is `string | InlayHintLabelPart[]`. Servers
    # that want per-part tooltips/commands use the array form; we
    # only render the text.
    def inlay_hint_label_text(hint)
      label = hint[:label]
      case label
      when String then label
      when Array
        label.map { |part| part.is_a?(Hash) ? part[:value].to_s : part.to_s }.join
      else ''
      end
    end

    # SGR for inlay-hint ghost text: italic + a muted gray foreground.
    # Italic alone isn't enough — terminals without italic support
    # would collapse the hint into the surrounding text — so we also
    # pin the color so it reads as "not real code" regardless.
    INLAY_HINT_SGR_OPEN  = "\e[3;38;5;240m"
    INLAY_HINT_SGR_CLOSE = "\e[23;39m"

    # Wrap one hint in the ghost-text SGR plus optional padding spaces.
    def format_inlay_hint(hint)
      text = inlay_hint_label_text(hint)
      return '' if text.empty?

      buf = +INLAY_HINT_SGR_OPEN
      buf << ' ' if hint[:paddingLeft]
      buf << text
      buf << ' ' if hint[:paddingRight]
      buf << INLAY_HINT_SGR_CLOSE
      buf
    end

    # SGR foreground colors per semantic token type. Picked to avoid
    # collision with the syntax highlighter's regex-driven palette
    # for the same tokens (so where ruby-lsp labels things, the color
    # is consistent with what users expect; where it doesn't, the
    # regex highlighter's colors stay visible).
    SEMANTIC_TOKEN_COLORS = {
      'namespace'     => 178, # gold
      'type'          => 178,
      'class'         => 178,
      'enum'          => 178,
      'interface'     => 178,
      'struct'        => 178,
      'typeParameter' => 178,
      'parameter'     => 215, # light orange
      'variable'      => 252, # light gray
      'property'      => 215,
      'enumMember'    => 209, # orange
      'function'      => 81,  # cyan
      'method'        => 81,
      'macro'         => 207, # magenta
      'keyword'       => 197, # pink
      'modifier'      => 197,
      'comment'       => 102, # medium gray
      'string'        => 150, # light green
      'number'        => 209, # orange
      'regexp'        => 207,
      'operator'      => 250, # near-white gray
      'decorator'     => 215,
    }.freeze

    # Splice fg-color SGR around each semantic token. SGR-aware walk
    # like the other overlays: step bytes while counting characters,
    # convert each token's (char_start, length) into byte positions,
    # and wrap that range in `\e[38;5;Cm ... \e[39m`.
    def apply_semantic_tokens_overlay(rendered, tokens, raw_line)
      return rendered if tokens.nil? || tokens.empty?

      byte_ranges = tokens.filter_map do |t|
        s = t[:start].to_i
        e = s + t[:length].to_i
        color = SEMANTIC_TOKEN_COLORS[t[:type]]
        next unless color

        sb = char_to_byte(raw_line, s)
        eb = char_to_byte(raw_line, e)
        next if sb >= eb

        [sb, eb, color]
      end.sort_by(&:first)
      return rendered if byte_ranges.empty?

      out = +''
      pos = 0
      orig = 0
      idx = 0
      active = nil
      total = rendered.bytesize

      while pos < total
        if rendered.getbyte(pos) == 0x1b && (m = rendered.byteslice(pos..-1)&.match(DIAG_SGR_RE))
          out << m[0]
          pos += m[0].bytesize
          next
        end

        if active && orig >= active[1]
          out << "\e[39m"
          active = nil
          idx += 1
        end

        if active.nil? && idx < byte_ranges.size && orig >= byte_ranges[idx][0]
          active = byte_ranges[idx]
          out << "\e[38;5;#{active[2]}m"
        end

        cb = rendered.getbyte(pos)
        char_bytes = if cb.nil? || cb < 0x80 then 1
                     elsif cb < 0xc0 then 1
                     elsif cb < 0xe0 then 2
                     elsif cb < 0xf0 then 3
                     else 4
                     end
        out << rendered.byteslice(pos, char_bytes)
        pos += char_bytes
        orig += char_bytes
      end

      out << "\e[39m" if active
      out
    end

    # Subtle dark-gray background for document-highlight occurrences.
    # Distinct from the diagnostic underline (which uses fg color +
    # underline) so the two can co-occur on the same span without
    # collision.
    DOC_HIGHLIGHT_BG_OPEN  = "\e[48;5;240m"
    DOC_HIGHLIGHT_BG_CLOSE = "\e[49m"

    # Splice document-highlight background SGR around each occurrence
    # of the cursor symbol on the line. LSP returns character ranges
    # (not bytes); we convert via the original line's char-to-byte
    # offsets, then walk the rendered line SGR-aware (same approach as
    # apply_diagnostic_overlay).
    # Collect every extmark across every namespace whose [line, ...]
    # range covers `line_idx`. Single-line marks count when their
    # `line == line_idx`; multi-line marks count when line_idx is
    # within [line, end_row]. Returned as Array<{ start_byte:,
    # end_byte:, hl_group:, priority: }>.
    def extmarks_intersecting(buffer, line_idx)
      hits = []
      return hits unless buffer.instance_variable_get(:@extmarks)

      buffer.extmarks.each_value do |marks|
        marks.each_value do |m|
          ml = m[:line] || 0
          el = m[:end_row] || m[:line] || 0
          next if line_idx < ml || line_idx > el
          next if m[:hl_group].nil? || m[:hl_group].to_s.empty?

          # Compute the byte range to span on THIS line.
          start_byte = (line_idx == ml) ? m[:col].to_i : 0
          end_byte = if line_idx == el
                       m[:end_col] ? m[:end_col].to_i : (buffer.lines[line_idx] || '').bytesize
                     else
                       (buffer.lines[line_idx] || '').bytesize
                     end
          next if end_byte <= start_byte

          hits << {
            start_byte: start_byte,
            end_byte: end_byte,
            hl_group: m[:hl_group].to_s,
            priority: (m[:priority] || 100).to_i,
          }
        end
      end
      hits.sort_by! { |h| h[:priority] }
      hits
    end

    # Splice extmark SGR around each span. Like apply_diagnostic_overlay
    # but the open/close pair comes from HighlightGroups; SGR-aware walk
    # so embedded syntax-highlight escapes pass through intact.
    def apply_extmark_overlay(rendered, marks, _raw_line)
      return rendered if marks.empty?

      # Resolve hl_group -> SGR open/close lazily; skip groups
      # without a registered definition (no visible effect).
      typed = marks.filter_map do |m|
        pair = @editor.hl_groups.lookup(m[:hl_group])
        next unless pair

        [m[:start_byte], m[:end_byte], pair.open, pair.close, m[:priority]]
      end.sort_by { |s, _e, _o, _c, p| [p, s] }
      return rendered if typed.empty?

      out = +''
      pos = 0
      orig = 0
      idx = 0
      active = nil # [end_byte, close_seq]
      total = rendered.bytesize
      while pos < total
        if rendered.getbyte(pos) == 0x1b && (m = rendered.byteslice(pos..-1)&.match(DIAG_SGR_RE))
          out << m[0]
          pos += m[0].bytesize
          next
        end

        if active && orig >= active[0]
          out << active[1]
          active = nil
          idx += 1
        end

        if active.nil? && idx < typed.size && orig >= typed[idx][0]
          active = [typed[idx][1], typed[idx][3]]
          out << typed[idx][2]
        end

        cb = rendered.getbyte(pos)
        char_bytes = if cb.nil? || cb < 0x80 then 1
                     elsif cb < 0xc0 then 1
                     elsif cb < 0xe0 then 2
                     elsif cb < 0xf0 then 3
                     else 4
                     end
        out << rendered.byteslice(pos, char_bytes)
        pos += char_bytes
        orig += char_bytes
      end
      out << active[1] if active
      out
    end

    def apply_document_highlight_overlay(rendered, highlights, raw_line)
      return rendered if highlights.nil? || highlights.empty?

      byte_ranges = highlights.filter_map do |hl|
        s_line = hl.dig(:range, :start, :line)
        e_line = hl.dig(:range, :end,   :line)
        s_char = hl.dig(:range, :start, :character).to_i
        e_char = hl.dig(:range, :end,   :character).to_i
        # Only render hits anchored on this single line — multi-line
        # highlights are rare in practice (single-symbol refs).
        next if s_line != e_line

        s_byte = char_to_byte(raw_line, s_char)
        e_byte = char_to_byte(raw_line, e_char)
        next if s_byte >= e_byte

        [s_byte, e_byte]
      end.sort_by(&:first)
      return rendered if byte_ranges.empty?

      out = +''
      pos = 0
      orig = 0
      idx = 0
      active_end = nil
      total = rendered.bytesize

      while pos < total
        if rendered.getbyte(pos) == 0x1b && (m = rendered.byteslice(pos..-1)&.match(DIAG_SGR_RE))
          out << m[0]
          pos += m[0].bytesize
          next
        end

        if active_end && orig >= active_end
          out << DOC_HIGHLIGHT_BG_CLOSE
          active_end = nil
          idx += 1
        end

        if active_end.nil? && idx < byte_ranges.size && orig >= byte_ranges[idx][0]
          active_end = byte_ranges[idx][1]
          out << DOC_HIGHLIGHT_BG_OPEN
        end

        cb = rendered.getbyte(pos)
        char_bytes = if cb.nil? || cb < 0x80 then 1
                     elsif cb < 0xc0 then 1
                     elsif cb < 0xe0 then 2
                     elsif cb < 0xf0 then 3
                     else 4
                     end
        out << rendered.byteslice(pos, char_bytes)
        pos += char_bytes
        orig += char_bytes
      end

      out << DOC_HIGHLIGHT_BG_CLOSE if active_end
      out
    end

    # Convert a 0-based character column on `line` into a byte offset.
    # LSP ranges are in UTF-16 code units by default, but ruby-lsp
    # (and our request) opt into UTF-8 code unit semantics, so a
    # char-index is a UTF-8 character index here.
    def char_to_byte(line, char_idx)
      return 0 if char_idx <= 0
      return line.bytesize if char_idx >= line.length

      line[0, char_idx].bytesize
    end

    DEFAULT_LISTCHARS = { 'tab' => '> ', 'trail' => '·' }.freeze

    def parse_listchars(spec)
      out = DEFAULT_LISTCHARS.dup
      spec.to_s.split(',').each do |pair|
        key, value = pair.split(':', 2)
        next if key.nil? || value.nil?

        out[key.strip] = value
      end
      out
    end

    def render_tab_marker(spec, width)
      head = spec[0] || '>'
      fill = spec[1] || ' '
      return head if width <= 1

      head + (fill * (width - 1))
    end

    def mark_trailing_whitespace(str, marker)
      safe = str.valid_encoding? ? str : str.scrub('?')
      safe.sub(/[ ]+\z/) { |trail| marker * trail.length }
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

    # Distinct style for the match the cursor is currently inside.
    # The terminal renders the text cursor by inverting the cell;
    # over a REVERSE-styled match that inversion cancels out and the
    # cursor becomes invisible. An explicit bg+fg pair keeps the
    # cursor's inversion visible (matches NeoVim's CurSearch).
    CURSEARCH_OPEN  = "\e[48;5;220;38;5;232m"
    CURSEARCH_CLOSE = "\e[39;49m"

    def apply_search_highlight(line, line_index, matches, width)
      ranges = matches.select { |l, _, _| l == line_index }.map { |_, s, e| [s, e] }
      cursor_byte = (@editor.line_index == line_index) ? @editor.byte_pointer : nil
      out = line.dup
      added = 0
      ranges.sort_by { |s, _| -s }.each do |s, e|
        first = snap_to_char_boundary(out, [s, out.bytesize].min)
        last = snap_to_char_boundary(out, [e + 1, out.bytesize].min)
        head = out.byteslice(0, first) || +''
        mid = out.byteslice(first, last - first) || +''
        tail = out.byteslice(last, out.bytesize - last) || +''
        current = cursor_byte && s <= cursor_byte && cursor_byte <= e
        open, close = current ? [CURSEARCH_OPEN, CURSEARCH_CLOSE] : [REVERSE_ON, REVERSE_OFF]
        out = head + open + mid + close + tail
        added += open.bytesize + close.bytesize
      end
      truncate(out, width + added)
    end

    def splice_highlight(line, first, last, width)
      first = snap_to_char_boundary(line, [first, line.bytesize].min)
      last = snap_to_char_boundary(line, [last, line.bytesize].min)
      head = line.byteslice(0, first) || ''
      mid = line.byteslice(first, last - first) || ''
      tail = line.byteslice(last, line.bytesize - last) || ''
      truncate(head + REVERSE_ON + mid + REVERSE_OFF + tail, width + REVERSE_ON.size + REVERSE_OFF.size)
    end

    def window_status(win, is_current)
      spec = @editor.settings.get(:statusline).to_s
      unless spec.empty?
        formatted = Rvim::Statusline.format(spec, @editor, win, is_current: is_current)
        return Rvim::Statusline.align_to_width(formatted, win.width)
      end

      buffer = win.buffer
      mode = (is_current && @editor.settings.get(:showmode)) ? mode_label : ''
      name = buffer.display_name
      modified = (is_current ? @editor.modified : buffer.modified) ? ' [+]' : ''
      recording = is_current && @editor.recording_macro ? "  recording @#{@editor.recording_macro}" : ''
      ruler = if @editor.settings.get(:ruler)
                lines = is_current ? @editor.buffer_of_lines : buffer.lines
                total = lines.size
                ln_idx = is_current ? @editor.line_index : buffer.line_index
                bp = is_current ? @editor.byte_pointer : buffer.byte_pointer
                ln = ln_idx + 1
                col = bp + 1
                # Virtual / display column: count terminal cells consumed
                # by the chars before the cursor. Differs from `col` whenever
                # multibyte or wide characters precede the cursor on the line.
                vcol = display_column(lines[ln_idx], bp) + 1
                col_field = (vcol == col) ? "#{col}" : "#{col}-#{vcol}"
                pct = total.zero? ? 0 : (ln * 100 / total)
                "    #{ln},#{col_field}    #{pct}%"
              else
                ''
              end
      " #{mode} #{name}#{modified}#{ruler}#{recording}".lstrip.then { |s| " #{s}" }
    end

    # Number of terminal cells the part of `line` before `byte_pointer`
    # would occupy when rendered. Each ASCII char = 1 cell, each
    # East-Asian wide char = 2 cells, etc.
    def display_column(line, byte_pointer)
      return 0 if line.nil? || byte_pointer <= 0

      end_byte = [byte_pointer, line.bytesize].min
      # Snap BACK to the leading byte of the codepoint the cursor is "on" so
      # the cursor's display column reflects the start of its character,
      # not the end (matching vim's semantics: cursor sits on a char,
      # never between bytes).
      end_byte = Rvim::DisplayMotion.snap_back_to_char_boundary(line, end_byte)
      slice = line.byteslice(0, end_byte) || ''
      Reline::Unicode.calculate_width(slice.to_s)
    rescue ArgumentError
      0
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
      if @editor.confirm_question
        return "#{@editor.confirm_question} (#{@editor.confirm_options.join('/')}): "
      end

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

    # (consolidated into the snap-aware display_column above)

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
      # Strings can arrive tagged ASCII-8BIT (e.g. when a plugin pushed
      # UTF-8 box-drawing bytes through rufus-lua, which doesn't carry
      # the encoding label). force_encoding to UTF-8 first so the
      # downstream `.encode` inside Reline's calculator doesn't error
      # on the byte-by-byte ASCII→UTF-8 attempt.
      utf = str.encoding == Encoding::UTF_8 ? str : String.new(str.b, encoding: Encoding::UTF_8)
      safe = utf.valid_encoding? ? utf : utf.scrub('?')
      no_ansi = safe.gsub(/\e\[[\d;]*[a-zA-Z]/, '')
      Reline::Unicode.calculate_width(no_ansi)
    end

    # Move `byte` forward until it lands on a UTF-8 character boundary so
    # that subsequent byteslice(...) returns a valid string. A multibyte
    # char's continuation bytes are 10xxxxxx (0x80..0xBF); leading bytes are
    # outside that range. Without this, slicing in the middle of e.g. 'あ'
    # produces an invalid byte sequence and downstream regex/width work
    # raises ArgumentError.
    def snap_to_char_boundary(line, byte)
      return byte if byte <= 0 || byte >= line.bytesize

      while byte < line.bytesize
        b = line.getbyte(byte)
        break if b.nil?
        break if b < 0x80 || b >= 0xC0 # ASCII or UTF-8 leading byte

        byte += 1
      end
      byte
    end

    def move_to(row, col)
      "\e[#{row};#{col}H"
    end
  end
end
