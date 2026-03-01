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
    ERASE_LINE = "\e[2K"

    def initialize(editor)
      @editor = editor
      @scroll_top = 0
      @prev_lines = []
      @rows = 24
      @cols = 80
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
      visible = visible_rows
      adjust_scroll(visible)

      out = +HIDE_CURSOR
      visible.times do |i|
        idx = @scroll_top + i
        line = if idx < @editor.buffer_of_lines.size
                 render_line(@editor.buffer_of_lines[idx])
               else
                 '~'
               end
        out << move_to(i + 1, 1) << ERASE_LINE << truncate(line, @cols)
      end

      out << move_to(@rows - 1, 1) << ERASE_LINE << REVERSE_ON
      out << truncate(status_line, @cols).ljust(@cols)
      out << REVERSE_OFF

      out << move_to(@rows, 1) << ERASE_LINE << bottom_line

      cursor_row = @editor.line_index - @scroll_top + 1
      cursor_col = display_column(@editor.buffer_of_lines[@editor.line_index] || '', @editor.byte_pointer) + 1
      if @editor.command_mode
        out << move_to(@rows, @editor.command_buffer.length + 2)
      else
        out << move_to(cursor_row, cursor_col)
      end
      out << SHOW_CURSOR

      $stdout.write(out)
      $stdout.flush
    end

    private

    def visible_rows
      [@rows - 2, 1].max
    end

    def adjust_scroll(visible)
      if @editor.line_index < @scroll_top
        @scroll_top = @editor.line_index
      elsif @editor.line_index >= @scroll_top + visible
        @scroll_top = @editor.line_index - visible + 1
      end
      @scroll_top = 0 if @scroll_top.negative?
    end

    def render_line(line)
      line.gsub("\t", '        ')
    end

    def status_line
      mode = mode_label
      name = @editor.filepath || '[No Name]'
      modified = @editor.modified ? ' [+]' : ''
      total = @editor.buffer_of_lines.size
      ln = @editor.line_index + 1
      col = @editor.byte_pointer + 1
      pct = total.zero? ? 0 : (ln * 100 / total)
      " #{mode} #{name}#{modified}    #{ln},#{col}    #{pct}%"
    end

    def mode_label
      case @editor.editing_mode_label
      when :vi_insert then '[Insert]'
      when :vi_command then '[Normal]'
      when :emacs then '[Emacs]'
      else "[#{@editor.editing_mode_label}]"
      end
    end

    def bottom_line
      if @editor.command_mode
        ":#{@editor.command_buffer}"
      elsif @editor.status_message
        @editor.status_message.to_s
      else
        ''
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
