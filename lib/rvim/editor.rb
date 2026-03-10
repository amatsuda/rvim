# frozen_string_literal: true

require 'reline'

module Rvim
  class Editor < Reline::LineEditor
    attr_reader :filepath, :visual_mode, :visual_anchor, :prompt_mode, :prompt_buffer
    attr_accessor :modified, :status_message

    def initialize(config)
      super
      @config.editing_mode = :vi_command
      multiline_on
      # Never terminate the multiline buffer — Enter always inserts a newline.
      self.confirm_multiline_termination_proc = ->(_buffer) { false }
      @filepath = nil
      @modified = false
      @quit = false
      @prompt_mode = nil
      @prompt_buffer = +''
      @status_message = nil
      @visual_mode = nil
      @visual_anchor = nil
      @last_visual = nil
      @rvim_text_object_pending = nil
      @rvim_visual_textobj_pending = nil
      @search_pattern = nil
      @search_direction = :forward
      @search_matches = []
      install_key_bindings
    end

    attr_reader :search_pattern, :search_direction, :search_matches

    private def install_key_bindings
      @config.add_default_key_binding_by_keymap(:vi_command, [?g.ord], :rvim_g_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?o.ord], :rvim_open_below)
      @config.add_default_key_binding_by_keymap(:vi_command, [?O.ord], :rvim_open_above)
      @config.add_default_key_binding_by_keymap(:vi_command, [?Z.ord], :rvim_z_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?:.ord], :rvim_enter_command_mode)
      @config.add_default_key_binding_by_keymap(:vi_command, [?/.ord], :rvim_enter_search_forward)
      @config.add_default_key_binding_by_keymap(:vi_command, [??.ord], :rvim_enter_search_backward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?n.ord], :rvim_search_next)
      @config.add_default_key_binding_by_keymap(:vi_command, [?N.ord], :rvim_search_prev)
      @config.add_default_key_binding_by_keymap(:vi_command, [?*.ord], :rvim_search_word_forward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?#.ord], :rvim_search_word_backward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?u.ord], :undo)
      @config.add_default_key_binding_by_keymap(:vi_command, [0x12], :redo) # Ctrl-R
      @config.add_default_key_binding_by_keymap(:vi_command, [?p.ord], :rvim_paste_after)
      @config.add_default_key_binding_by_keymap(:vi_command, [?P.ord], :rvim_paste_before)
      @config.add_default_key_binding_by_keymap(:vi_command, [?v.ord], :rvim_visual_char)
      @config.add_default_key_binding_by_keymap(:vi_command, [?V.ord], :rvim_visual_line)
      @config.add_default_key_binding_by_keymap(:vi_command, [0x16], :rvim_visual_block) # Ctrl-V
      @config.add_default_key_binding_by_keymap(:vi_command, [?>.ord], :rvim_shift_right_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?<.ord], :rvim_shift_left_prefix)
    end

    def open(path)
      if File.exist?(path)
        lines = File.readlines(path, chomp: true)
        @buffer_of_lines = lines.empty? ? [+''] : lines.map { |l| String.new(l, encoding: encoding) }
      else
        @buffer_of_lines = [+'']
      end
      @filepath = path
      @line_index = 0
      @byte_pointer = 0
    end

    def save(path = nil)
      target = path || @filepath
      raise 'no file path' unless target

      content = @buffer_of_lines.join("\n")
      content += "\n" unless content.end_with?("\n")
      File.write(target, content)
      @filepath = target
      @modified = false
    end

    def quit?
      @quit
    end

    def quit!
      @quit = true
    end

    def buffer_of_lines
      @buffer_of_lines
    end

    def line_index
      @line_index
    end

    def byte_pointer
      @byte_pointer
    end

    def editing_mode_label
      @config.instance_variable_get(:@editing_mode_label)
    end

    def screen=(screen)
      @screen = screen
    end

    def render
      @screen&.render
    end

    def update(key)
      if @prompt_mode
        process_prompt_key(key)
      elsif @visual_mode
        return if intercept_visual_key(key)

        before = @buffer_of_lines.map(&:dup)
        super
        @modified = true if before != @buffer_of_lines
      elsif @rvim_text_object_pending
        consume_text_object_key(key)
      elsif operator_pending? && text_object_prefix?(key)
        @rvim_text_object_pending = key.char == 'a' ? :around : :inner
      else
        @status_message = nil
        before = @buffer_of_lines.map(&:dup)
        super
        @modified = true if before != @buffer_of_lines
      end
    end

    private def operator_pending?
      !@vi_waiting_operator.nil?
    end

    private def text_object_prefix?(key)
      key.char == 'i' || key.char == 'a'
    end

    private def consume_visual_text_object_key(key)
      inclusive = @rvim_visual_textobj_pending == :around
      @rvim_visual_textobj_pending = nil

      return if key.char == "\e"

      range = Rvim::TextObject.find(key.char, self, inclusive: inclusive)
      return unless range

      @visual_anchor = [range.start_line, range.start_col]
      move_cursor_to(range.end_line, range.end_col)
      @visual_mode = range.linewise? ? :line : :char
    end

    private def consume_text_object_key(key)
      inclusive = @rvim_text_object_pending == :around
      @rvim_text_object_pending = nil

      if key.char == "\e"
        # Cancel the operator silently.
        @vi_waiting_operator = nil
        @vi_waiting_operator_arg = nil
        return
      end

      range = Rvim::TextObject.find(key.char, self, inclusive: inclusive)
      if range
        before = @buffer_of_lines.map(&:dup)
        apply_pending_operator_to_range(range)
        @modified = true if @buffer_of_lines != before
      end

      @vi_waiting_operator = nil
      @vi_waiting_operator_arg = nil
    end

    private def apply_pending_operator_to_range(sel)
      case @vi_waiting_operator
      when :vi_delete_meta_confirm
        Rvim::Operations.delete(self, sel)
      when :vi_change_meta_confirm
        Rvim::Operations.change(self, sel)
      when :vi_yank_confirm
        Rvim::Operations.yank(self, sel)
      end
    end

    def selection
      return nil unless @visual_mode

      Rvim::Selection.from(
        @visual_mode,
        @visual_anchor,
        [@line_index, @byte_pointer],
        @buffer_of_lines,
      )
    end

    # Returns true if the key was fully handled and update should not call super.
    private def intercept_visual_key(key)
      ch = key.char
      sym = key.method_symbol
      if ch == "\e"
        exit_visual
        return true
      end
      case sym
      when :rvim_visual_char then switch_visual_mode(:char); return true
      when :rvim_visual_line then switch_visual_mode(:line); return true
      when :rvim_visual_block then switch_visual_mode(:block); return true
      end
      if @rvim_visual_textobj_pending
        consume_visual_text_object_key(key)
        return true
      end

      case ch
      when ':'
        exit_visual
        @prompt_mode = :ex
        @prompt_buffer = +"'<,'>"
        @status_message = nil
        return true
      when 'i', 'a'
        @rvim_visual_textobj_pending = (ch == 'a' ? :around : :inner)
        return true
      when 'o'
        if @visual_anchor
          new_anchor = [@line_index, @byte_pointer]
          al, ac = @visual_anchor
          move_cursor_to(al, ac)
          @visual_anchor = new_anchor
        end
        return true
      when 'y'
        sel = selection
        Rvim::Operations.yank(self, sel) if sel
        exit_visual
        return true
      when 'd', 'x'
        sel = selection
        if sel
          Rvim::Operations.delete(self, sel)
          @modified = true
        end
        exit_visual
        return true
      when 'c', 's'
        sel = selection
        if sel
          Rvim::Operations.change(self, sel)
          @modified = true
        end
        exit_visual
        return true
      when '>'
        sel = selection
        if sel
          Rvim::Operations.shift_right(self, sel)
          @modified = true
        end
        exit_visual
        return true
      when '<'
        sel = selection
        if sel
          Rvim::Operations.shift_left(self, sel)
          @modified = true
        end
        exit_visual
        return true
      when '~'
        sel = selection
        if sel
          Rvim::Operations.toggle_case(self, sel)
          @modified = true
        end
        exit_visual
        return true
      end
      false
    end

    def config
      @config
    end

    def set_clipboard(content, kind)
      @rvim_clipboard = content
      @rvim_clipboard_kind = kind
      # legacy linewise flag for compatibility with v1's dd/p path
      @rvim_clipboard_linewise = (kind == :line)
    end

    def move_cursor_to(line, byte)
      @line_index = line.clamp(0, [@buffer_of_lines.size - 1, 0].max)
      target = @buffer_of_lines[@line_index] || ''
      @byte_pointer = byte.clamp(0, target.bytesize)
    end

    private def switch_visual_mode(mode)
      if @visual_mode == mode
        exit_visual
      else
        @visual_mode = mode
        @visual_anchor ||= [@line_index, @byte_pointer]
      end
    end

    private def enter_visual(mode)
      @visual_mode = mode
      @visual_anchor = [@line_index, @byte_pointer]
    end

    private def exit_visual
      if @visual_mode && @visual_anchor
        @last_visual = {
          mode: @visual_mode,
          anchor: @visual_anchor.dup,
          last_end: [@line_index, @byte_pointer],
        }
      end
      @visual_mode = nil
      @visual_anchor = nil
    end

    private def rvim_visual_char(key)
      enter_visual(:char)
    end

    private def rvim_visual_line(key)
      enter_visual(:line)
    end

    private def rvim_visual_block(key)
      enter_visual(:block)
    end

    private def process_prompt_key(key)
      ch = key.char
      if ch.nil?
        cancel_prompt
        return
      end
      case ch
      when "\r", "\n"
        execute_prompt
        return
      when "\e"
        cancel_prompt
        return
      when "\x7f", "\b" # backspace / DEL
        if @prompt_buffer.empty?
          cancel_prompt
          return
        else
          @prompt_buffer.chop!
        end
      else
        @prompt_buffer << ch.to_s
      end
      refresh_incremental_search
    end

    private def refresh_incremental_search
      return unless @prompt_mode == :search_forward || @prompt_mode == :search_backward

      @search_matches = Rvim::Search.scan(@buffer_of_lines, @prompt_buffer)
    end

    private def execute_prompt
      case @prompt_mode
      when :ex
        parsed = Rvim::Command.parse(@prompt_buffer)
        Rvim::Command.execute(self, parsed) if parsed
        reset_prompt
      when :search_forward, :search_backward
        commit_search
      else
        reset_prompt
      end
    end

    private def cancel_prompt
      was_search = @prompt_mode == :search_forward || @prompt_mode == :search_backward
      reset_prompt
      @status_message = nil
      # Clear the incremental highlight if we cancel mid-search; preserve any
      # previously committed @search_pattern by re-scanning for it.
      if was_search
        @search_matches = @search_pattern ? Rvim::Search.scan(@buffer_of_lines, @search_pattern) : []
      end
    end

    private def reset_prompt
      @prompt_mode = nil
      @prompt_buffer = +''
    end

    private def rvim_enter_command_mode(key)
      @prompt_mode = :ex
      @prompt_buffer = +''
      @status_message = nil
    end

    private def rvim_enter_search_forward(key)
      @prompt_mode = :search_forward
      @prompt_buffer = +''
      @status_message = nil
    end

    private def rvim_enter_search_backward(key)
      @prompt_mode = :search_backward
      @prompt_buffer = +''
      @status_message = nil
    end

    private def rvim_search_next(key)
      jump_to_search(@search_direction)
    end

    private def rvim_search_prev(key)
      reverse = @search_direction == :forward ? :backward : :forward
      jump_to_search(reverse)
    end

    private def rvim_search_word_forward(key)
      search_word_under_cursor(:forward)
    end

    private def rvim_search_word_backward(key)
      search_word_under_cursor(:backward)
    end

    private def search_word_under_cursor(direction)
      word = word_at_cursor
      return unless word

      pattern = "\\b#{Regexp.escape(word)}\\b"
      matches = Rvim::Search.scan(@buffer_of_lines, pattern)
      if matches.empty?
        @status_message = "E486: Pattern not found: #{word}"
        return
      end
      @search_pattern = pattern
      @search_direction = direction
      @search_matches = matches
      target = Rvim::Search.next_match(matches, @line_index, @byte_pointer, direction)
      move_cursor_to(target[0], target[1]) if target
    end

    private def word_at_cursor
      line = @buffer_of_lines[@line_index] || ''
      return nil if line.empty?

      pos = [@byte_pointer, line.bytesize - 1].min
      ch = line.byteslice(pos, 1)
      return nil unless ch && ch =~ /\w/

      start_byte = pos
      start_byte -= 1 while start_byte > 0 && line.byteslice(start_byte - 1, 1) =~ /\w/
      end_byte = pos
      end_byte += 1 while end_byte < line.bytesize - 1 && line.byteslice(end_byte + 1, 1) =~ /\w/
      line.byteslice(start_byte, end_byte - start_byte + 1)
    end

    private def jump_to_search(direction)
      return unless @search_pattern

      @search_matches = Rvim::Search.scan(@buffer_of_lines, @search_pattern) if @search_matches.empty?
      target = Rvim::Search.next_match(@search_matches, @line_index, @byte_pointer, direction)
      if target
        move_cursor_to(target[0], target[1])
      else
        @status_message = "E486: Pattern not found: #{@search_pattern}"
      end
    end

    private def commit_search
      pattern = @prompt_buffer.dup
      direction = @prompt_mode == :search_forward ? :forward : :backward
      reset_prompt
      return if pattern.empty?

      matches = Rvim::Search.scan(@buffer_of_lines, pattern)
      if matches.empty?
        @status_message = "E486: Pattern not found: #{pattern}"
        return
      end

      @search_pattern = pattern
      @search_direction = direction
      @search_matches = matches
      target = Rvim::Search.next_match(matches, @line_index, @byte_pointer, direction, include_start: true)
      move_cursor_to(target[0], target[1]) if target
    end

    # Backcompat readers used by Screen for the prompt-mode rendering.
    def command_mode
      @prompt_mode == :ex
    end

    def command_buffer
      @prompt_buffer
    end

    private def ed_prev_history(key, arg: 1)
      arg.times do
        break if @line_index <= 0

        cursor = current_byte_pointer_cursor
        @line_index -= 1
        calculate_nearest_cursor(cursor)
      end
    end

    private def ed_next_history(key, arg: 1)
      arg.times do
        break if @line_index >= @buffer_of_lines.size - 1

        cursor = current_byte_pointer_cursor
        @line_index += 1
        calculate_nearest_cursor(cursor)
      end
    end

    private def vi_to_history_line(key, arg: nil)
      target = arg.is_a?(Integer) && arg > 0 ? arg - 1 : @buffer_of_lines.size - 1
      @line_index = target.clamp(0, @buffer_of_lines.size - 1)
      @byte_pointer = 0
    end

    private def rvim_g_prefix(key)
      @waiting_proc = lambda do |key_for_proc, _sym|
        @waiting_proc = nil
        case key_for_proc
        when 'g', 'g'.ord
          @line_index = 0
          @byte_pointer = 0
        when 'v', 'v'.ord
          reselect_last_visual
        end
      end
    end

    private def reselect_last_visual
      return unless @last_visual

      @visual_mode = @last_visual[:mode]
      @visual_anchor = @last_visual[:anchor].dup
      le, lc = @last_visual[:last_end]
      move_cursor_to(le, lc)
    end

    private def rvim_open_below(key)
      @buffer_of_lines.insert(@line_index + 1, String.new(encoding: encoding))
      @line_index += 1
      @byte_pointer = 0
      @config.editing_mode = :vi_insert
    end

    private def rvim_open_above(key)
      @buffer_of_lines.insert(@line_index, String.new(encoding: encoding))
      @byte_pointer = 0
      @config.editing_mode = :vi_insert
    end

    private def rvim_shift_right_prefix(key, arg: 1)
      count = arg
      @waiting_proc = lambda do |key_for_proc, _sym|
        @waiting_proc = nil
        if key_for_proc == '>' || key_for_proc == '>'.ord
          shift_lines_at_cursor(count, direction: :right)
        end
      end
    end

    private def rvim_shift_left_prefix(key, arg: 1)
      count = arg
      @waiting_proc = lambda do |key_for_proc, _sym|
        @waiting_proc = nil
        if key_for_proc == '<' || key_for_proc == '<'.ord
          shift_lines_at_cursor(count, direction: :left)
        end
      end
    end

    private def shift_lines_at_cursor(count, direction:)
      end_line = [@line_index + count - 1, @buffer_of_lines.size - 1].min
      sel = Rvim::Selection.from(:line, [@line_index, 0], [end_line, 0], @buffer_of_lines)
      if direction == :right
        Rvim::Operations.shift_right(self, sel)
      else
        Rvim::Operations.shift_left(self, sel)
      end
      @modified = true
    end

    private def vi_delete_meta(key, arg: nil)
      if @vi_waiting_operator == :vi_delete_meta_confirm && arg.nil?
        count = @vi_waiting_operator_arg || 1
        delete_lines_linewise(count)
        @vi_waiting_operator = nil
        @vi_waiting_operator_arg = nil
        return
      end
      super
    end

    private def vi_delete_meta_confirm(byte_pointer_diff)
      capture_charwise(byte_pointer_diff)
      super
    end

    private def vi_change_meta(key, arg: nil)
      if @vi_waiting_operator == :vi_change_meta_confirm && arg.nil?
        count = @vi_waiting_operator_arg || 1
        change_lines_linewise(count)
        @vi_waiting_operator = nil
        @vi_waiting_operator_arg = nil
        return
      end
      super
    end

    private def vi_change_meta_confirm(byte_pointer_diff)
      capture_charwise(byte_pointer_diff)
      super
    end

    private def vi_yank(key, arg: nil)
      if @vi_waiting_operator == :vi_yank_confirm && arg.nil?
        count = @vi_waiting_operator_arg || 1
        yank_lines_linewise(count)
        @vi_waiting_operator = nil
        @vi_waiting_operator_arg = nil
        return
      end
      super
    end

    private def vi_yank_confirm(byte_pointer_diff)
      capture_charwise(byte_pointer_diff)
      super
    end

    private def capture_charwise(byte_pointer_diff)
      return if byte_pointer_diff.zero?

      if byte_pointer_diff > 0
        cut = current_line.byteslice(@byte_pointer, byte_pointer_diff)
      else
        cut = current_line.byteslice(@byte_pointer + byte_pointer_diff, -byte_pointer_diff)
      end
      set_clipboard(cut.to_s, :char)
    end

    private def delete_lines_linewise(count)
      return if @buffer_of_lines.empty?

      count = [count, @buffer_of_lines.size - @line_index].min
      cut_lines = @buffer_of_lines.slice!(@line_index, count) || []
      set_clipboard(cut_lines.join("\n"), :line)
      if @buffer_of_lines.empty?
        @buffer_of_lines = [String.new(encoding: encoding)]
        @line_index = 0
      elsif @line_index >= @buffer_of_lines.size
        @line_index = @buffer_of_lines.size - 1
      end
      @byte_pointer = 0
    end

    private def yank_lines_linewise(count)
      count = [count, @buffer_of_lines.size - @line_index].min
      text = @buffer_of_lines[@line_index, count].join("\n")
      set_clipboard(text, :line)
    end

    private def change_lines_linewise(count)
      count = [count, @buffer_of_lines.size - @line_index].min
      cut_lines = @buffer_of_lines.slice!(@line_index, count) || []
      set_clipboard(cut_lines.join("\n"), :line)
      @buffer_of_lines.insert(@line_index, String.new(encoding: encoding))
      @byte_pointer = 0
      @config.editing_mode = :vi_insert
    end

    private def rvim_paste_after(key, arg: 1)
      case @rvim_clipboard_kind
      when :line
        paste_lines_after
      when :char
        paste_char_after
      when :block
        paste_block(after: true)
      else
        vi_paste_next(key, arg: arg)
      end
    end

    private def rvim_paste_before(key, arg: 1)
      case @rvim_clipboard_kind
      when :line
        paste_lines_before
      when :char
        paste_char_before
      when :block
        paste_block(after: false)
      else
        vi_paste_prev(key, arg: arg)
      end
    end

    private def paste_lines_after
      return unless @rvim_clipboard

      @rvim_clipboard.split("\n", -1).each_with_index do |line, i|
        @buffer_of_lines.insert(@line_index + 1 + i, String.new(line, encoding: encoding))
      end
      @line_index += 1
      @byte_pointer = 0
    end

    private def paste_lines_before
      return unless @rvim_clipboard

      @rvim_clipboard.split("\n", -1).each_with_index do |line, i|
        @buffer_of_lines.insert(@line_index + i, String.new(line, encoding: encoding))
      end
      @byte_pointer = 0
    end

    private def paste_char_after
      return unless @rvim_clipboard

      lines = @rvim_clipboard.split("\n", -1)
      current = @buffer_of_lines[@line_index] || (+'')
      insert_at = current.bytesize.zero? ? 0 : @byte_pointer + 1
      insert_at = [insert_at, current.bytesize].min

      head = current.byteslice(0, insert_at) || +''
      tail = current.byteslice(insert_at, current.bytesize - insert_at) || +''

      if lines.size == 1
        merged = head + lines.first + tail
        @buffer_of_lines[@line_index] = String.new(merged, encoding: encoding)
        @byte_pointer = insert_at + lines.first.bytesize - 1
        @byte_pointer = 0 if @byte_pointer.negative?
      else
        @buffer_of_lines[@line_index] = String.new(head + lines.first, encoding: encoding)
        last = String.new(lines.last + tail, encoding: encoding)
        middle = lines[1..-2] || []
        offset = 1
        middle.each do |m|
          @buffer_of_lines.insert(@line_index + offset, String.new(m, encoding: encoding))
          offset += 1
        end
        @buffer_of_lines.insert(@line_index + offset, last)
        @line_index += offset
        @byte_pointer = [lines.last.bytesize - 1, 0].max
      end
    end

    private def paste_char_before
      return unless @rvim_clipboard

      saved = @byte_pointer
      @byte_pointer = saved - 1
      @byte_pointer = -1 if @byte_pointer.negative?
      paste_char_after
    end

    private def paste_block(after:)
      return unless @rvim_clipboard

      base_line = @line_index
      base_col = @byte_pointer + (after ? 1 : 0)
      Array(@rvim_clipboard).each_with_index do |chunk, i|
        target_line = base_line + i
        @buffer_of_lines[target_line] ||= String.new('', encoding: encoding)
        line = @buffer_of_lines[target_line]
        col = [base_col, line.bytesize].min
        head = line.byteslice(0, col) || +''
        # pad if cursor is past EOL on this row
        pad = col > line.bytesize ? ' ' * (col - line.bytesize) : ''
        tail = line.byteslice(col, line.bytesize - col) || +''
        @buffer_of_lines[target_line] = String.new(head + pad + chunk.to_s + tail, encoding: encoding)
      end
      @line_index = base_line
      @byte_pointer = base_col
    end

    private def rvim_z_prefix(key)
      @waiting_proc = lambda do |key_for_proc, _sym|
        @waiting_proc = nil
        if key_for_proc == 'Z' || key_for_proc == 'Z'.ord
          save if @filepath
          @quit = true
        end
      end
    end

    def handle_signal
      if @interrupted
        @interrupted = false
        @quit = true
        raise Interrupt
      end
    end

    def self.start(filepath = nil)
      editor = new(Reline.core.config)
      editor.open(filepath) if filepath
      screen = Rvim::Screen.new(editor)
      editor.screen = screen

      Reline.core.line_editor = editor
      otio = nil
      begin
        otio = Reline::IOGate.prep
        screen.setup
        editor.set_signal_handlers
        Reline::IOGate.with_raw_input do
          loop do
            screen.render
            begin
              Reline.core.send(:read_io, Reline.core.config.keyseq_timeout) do |inputs|
                inputs.each do |key|
                  editor.set_pasting_state(Reline::IOGate.in_pasting?)
                  editor.update(key)
                end
              end
            rescue Interrupt
              editor.quit!
            end
            break if editor.quit?
          end
        end
      ensure
        editor&.finalize
        screen&.teardown
        Reline::IOGate.deprep(otio) if otio
      end
    end
  end
end
