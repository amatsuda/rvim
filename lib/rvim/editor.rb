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
      @change_keys = []
      @last_change_keys = []
      @replaying = false
      @macros = {}
      @recording_macro = nil
      @macro_keys = []
      @last_macro_register = nil
      @registers = Rvim::Registers.new
      @pending_register = nil
      @last_register_op = nil
      @marks = Rvim::Marks.new
      @global_marks = Rvim::GlobalMarks.new
      @jump_list = []
      @jump_index = 0
      @buffers = {}
      @buffer_order = []
      @next_buffer_id = 1
      @current_buffer = nil
      @windows = []
      @current_window = nil
      @split_orientation = nil
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
      @config.add_default_key_binding_by_keymap(:vi_command, [?..ord], :rvim_dot)
      @config.add_default_key_binding_by_keymap(:vi_command, [?q.ord], :rvim_q_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?@.ord], :rvim_at_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?".ord], :rvim_register_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?m.ord], :rvim_mark_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?'.ord], :rvim_mark_jump_line)
      @config.add_default_key_binding_by_keymap(:vi_command, [?`.ord], :rvim_mark_jump_exact)
      @config.add_default_key_binding_by_keymap(:vi_command, [0x0F], :rvim_jump_back)    # Ctrl-O
      @config.add_default_key_binding_by_keymap(:vi_command, [0x09], :rvim_jump_forward) # Ctrl-I (Tab)
      @config.add_default_key_binding_by_keymap(:vi_command, [0x17], :rvim_window_prefix) # Ctrl-W
    end

    def open(path)
      buf = find_or_create_buffer(path)
      swap_to_buffer(buf)
    end

    private def find_or_create_buffer(path)
      existing = @buffers.values.find { |b| b.filepath == path } if path
      return existing if existing

      buf = Rvim::Buffer.new(@next_buffer_id, path, encoding: encoding)
      @next_buffer_id += 1
      @buffers[buf.id] = buf
      @buffer_order << buf.id
      buf
    end

    def swap_to_buffer(buf)
      save_current_buffer if @current_buffer
      @current_buffer = buf
      @filepath = buf.filepath
      @buffer_of_lines = buf.lines
      @line_index = buf.line_index
      @byte_pointer = buf.byte_pointer
      @modified = buf.modified
      @marks = buf.marks
      @last_visual = buf.last_visual
      @undo_redo_history = buf.undo_redo_history
      @undo_redo_index = buf.undo_redo_index
      ensure_current_window(buf)
    end

    private def ensure_current_window(buf)
      if @windows.empty?
        win = Rvim::Window.new(buf)
        @windows << win
        @current_window = win
      else
        @current_window.buffer = buf if @current_window
      end
    end

    attr_reader :windows, :current_window, :split_orientation

    def split_horizontal(buffer = nil)
      return mixed_split_error if @split_orientation == :vertical && @windows.size > 1

      @split_orientation = :horizontal
      add_split(buffer)
    end

    def split_vertical(buffer = nil)
      return mixed_split_error if @split_orientation == :horizontal && @windows.size > 1

      @split_orientation = :vertical
      add_split(buffer)
    end

    private def add_split(buffer)
      target_buffer = buffer || @current_buffer
      win = Rvim::Window.new(target_buffer)
      win.scroll_top = @current_window&.scroll_top || 0
      idx = @windows.index(@current_window) || (@windows.size - 1)
      @windows.insert(idx + 1, win)
      @current_window = win
    end

    private def mixed_split_error
      @status_message = 'E36: Not enough room (mixed splits not supported)'
    end

    private def rvim_window_prefix(key)
      @waiting_proc = lambda do |k, _sym|
        @waiting_proc = nil
        ch = k.is_a?(Integer) ? k.chr : k.to_s
        case ch
        when 's', 'S' then split_horizontal
        when 'v', 'V' then split_vertical
        when 'h' then focus_window(:left)
        when 'j' then focus_window(:down)
        when 'k' then focus_window(:up)
        when 'l' then focus_window(:right)
        when 'w', "\x17" then focus_next_window
        when 'c' then close_current_window
        end
      end
    end

    def focus_window(direction)
      return if @windows.size < 2

      idx = @windows.index(@current_window) || 0
      target_idx = case direction
                   when :down, :right then idx + 1
                   when :up, :left    then idx - 1
                   end
      return if target_idx.nil? || target_idx < 0 || target_idx >= @windows.size

      activate_window(@windows[target_idx])
    end

    def focus_next_window
      return if @windows.size < 2

      idx = @windows.index(@current_window) || 0
      activate_window(@windows[(idx + 1) % @windows.size])
    end

    def close_current_window
      return if @windows.size < 2

      victim = @current_window
      idx = @windows.index(victim)
      @windows.delete(victim)
      @current_window = @windows[idx] || @windows.last
      @split_orientation = nil if @windows.size == 1
      activate_window(@current_window) if @current_window
    end

    private def activate_window(win)
      return unless win

      save_current_buffer if @current_buffer
      @current_window = win
      buf = win.buffer
      @current_buffer = buf
      @filepath = buf.filepath
      @buffer_of_lines = buf.lines
      @line_index = buf.line_index
      @byte_pointer = buf.byte_pointer
      @modified = buf.modified
      @marks = buf.marks
      @last_visual = buf.last_visual
      @undo_redo_history = buf.undo_redo_history
      @undo_redo_index = buf.undo_redo_index
    end

    private def save_current_buffer
      @current_buffer.lines = @buffer_of_lines
      @current_buffer.line_index = @line_index
      @current_buffer.byte_pointer = @byte_pointer
      @current_buffer.modified = @modified
      @current_buffer.marks = @marks
      @current_buffer.last_visual = @last_visual
      @current_buffer.undo_redo_history = @undo_redo_history
      @current_buffer.undo_redo_index = @undo_redo_index
      @current_buffer.filepath = @filepath
    end

    attr_reader :buffers, :current_buffer, :buffer_order

    def next_buffer
      cycle_buffer(+1)
    end

    def prev_buffer
      cycle_buffer(-1)
    end

    def cycle_buffer(direction)
      return if @buffer_order.size <= 1

      idx = @buffer_order.index(@current_buffer.id) || 0
      target_id = @buffer_order[(idx + direction) % @buffer_order.size]
      swap_to_buffer(@buffers[target_id])
    end

    def delete_current_buffer(force: false)
      return unless @current_buffer

      save_current_buffer
      if @current_buffer.modified && !force
        @status_message = 'E89: No write since last change (add ! to override)'
        return
      end

      victim_id = @current_buffer.id
      idx = @buffer_order.index(victim_id)
      @buffer_order.delete(victim_id)
      @buffers.delete(victim_id)

      if @buffer_order.empty?
        # Open an empty scratch buffer so we always have something to display.
        @current_buffer = nil
        scratch = Rvim::Buffer.new(@next_buffer_id, nil, encoding: encoding)
        @next_buffer_id += 1
        @buffers[scratch.id] = scratch
        @buffer_order << scratch.id
        swap_to_buffer(scratch)
      else
        fallback_id = @buffer_order[idx - 1] || @buffer_order.first
        @current_buffer = nil
        swap_to_buffer(@buffers[fallback_id])
      end
    end

    def switch_buffer_by(arg)
      target = if arg =~ /\A\d+\z/
                 @buffers[arg.to_i]
               else
                 @buffers.values.find { |b| b.display_name.include?(arg) }
               end
      if target
        swap_to_buffer(target)
      else
        @status_message = "E94: No matching buffer for #{arg}"
      end
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

    def quit!(exit_code: 0)
      @quit = true
      @exit_code = exit_code
    end

    def exit_code
      @exit_code || 0
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
      pre_idle = idle_for_recording?
      pre_buffer = @buffer_of_lines.map(&:dup)
      record_change_key(key, pre_idle) unless @replaying
      record_macro_key(key) unless @replaying

      if @prompt_mode
        process_prompt_key(key)
      elsif @visual_mode
        result = intercept_visual_key(key)
        unless result
          super
          @modified = true if pre_buffer != @buffer_of_lines
        end
      elsif @rvim_text_object_pending
        consume_text_object_key(key)
      elsif operator_pending? && text_object_prefix?(key)
        @rvim_text_object_pending = key.char == 'a' ? :around : :inner
      else
        @status_message = nil
        super
        @modified = true if pre_buffer != @buffer_of_lines
      end

      freeze_change_if_settled(pre_buffer) unless @replaying
    end

    private def idle_for_recording?
      @prompt_mode.nil? &&
        @visual_mode.nil? &&
        @vi_waiting_operator.nil? &&
        @rvim_text_object_pending.nil? &&
        @waiting_proc.nil? &&
        editing_mode_label == :vi_command
    end

    private def record_change_key(key, was_idle)
      if was_idle
        @change_keys = [key]
        @change_buffer_snapshot = @buffer_of_lines.map(&:dup)
      else
        @change_keys << key
      end
    end

    private def freeze_change_if_settled(_pre_buffer)
      return unless idle_for_recording?
      return if @change_buffer_snapshot.nil?
      return if @change_buffer_snapshot == @buffer_of_lines

      @last_change_keys = @change_keys.dup
      @change_keys = []
      @change_buffer_snapshot = nil
    end

    private def record_macro_key(key)
      return unless @recording_macro
      return if key.char == 'q' # the terminator stops recording rather than being captured

      @macro_keys << key
    end

    attr_reader :last_change_keys, :recording_macro

    private def rvim_register_prefix(key)
      @waiting_proc = lambda do |reg_key, _sym|
        @waiting_proc = nil
        ch = reg_key.is_a?(Integer) ? reg_key.chr : reg_key.to_s
        @pending_register = ch if ch =~ /\A[a-zA-Z0-9"+%]\z/
      end
    end

    private def rvim_mark_prefix(key)
      @waiting_proc = lambda do |reg_key, _sym|
        @waiting_proc = nil
        ch = charify(reg_key)
        if ch =~ /\A[A-Z]\z/
          @global_marks.set(ch, @current_buffer&.id, @line_index, @byte_pointer)
        else
          @marks.set(ch, @line_index, @byte_pointer)
        end
      end
    end

    def global_mark(name)
      entry = @global_marks.get(name)
      return nil unless entry

      buffer_id, line, col = entry
      [buffer_id, line, col]
    end

    private def rvim_mark_jump_line(key)
      @waiting_proc = lambda do |reg_key, _sym|
        @waiting_proc = nil
        jump_to_mark(charify(reg_key), line_only: true)
      end
    end

    private def rvim_mark_jump_exact(key)
      @waiting_proc = lambda do |reg_key, _sym|
        @waiting_proc = nil
        jump_to_mark(charify(reg_key), line_only: false)
      end
    end

    private def jump_to_mark(name, line_only:)
      pos = @marks.get(name, self)
      return unless pos

      line, col, target_buffer = if pos.size == 3
                                   bid, l, c = pos
                                   [l, c, @buffers[bid]]
                                 else
                                   [pos[0], pos[1], nil]
                                 end

      push_jump
      if target_buffer && target_buffer != @current_buffer
        swap_to_buffer(target_buffer)
      end

      if line_only
        line_text = @buffer_of_lines[line] || ''
        col = first_non_whitespace_col(line_text)
      end
      move_cursor_to(line, col)
    end

    private def charify(key)
      key.is_a?(Integer) ? key.chr : key.to_s
    end

    private def first_non_whitespace_col(line)
      i = 0
      i += 1 while i < line.bytesize && (line.byteslice(i, 1) == ' ' || line.byteslice(i, 1) == "\t")
      i
    end

    private def rvim_jump_back(key, arg: 1)
      arg.times do
        if @jump_index == @jump_list.size
          # First Ctrl-O from the tip: record current position so Ctrl-I can return.
          @jump_list << [@line_index, @byte_pointer]
        end
        break if @jump_index <= 0

        @jump_index -= 1
        line, col = @jump_list[@jump_index]
        @line_index = line.clamp(0, [@buffer_of_lines.size - 1, 0].max)
        target = @buffer_of_lines[@line_index] || ''
        @byte_pointer = col.clamp(0, target.bytesize)
      end
    end

    private def rvim_jump_forward(key, arg: 1)
      arg.times do
        break if @jump_index >= @jump_list.size - 1

        @jump_index += 1
        line, col = @jump_list[@jump_index]
        @line_index = line.clamp(0, [@buffer_of_lines.size - 1, 0].max)
        target = @buffer_of_lines[@line_index] || ''
        @byte_pointer = col.clamp(0, target.bytesize)
      end
    end

    JUMP_LIST_LIMIT = 100

    def push_jump(line = @line_index, col = @byte_pointer)
      @jump_list = @jump_list.first(@jump_index) if @jump_index < @jump_list.size
      @jump_list << [line, col]
      @jump_list.shift if @jump_list.size > JUMP_LIST_LIMIT
      @jump_index = @jump_list.size
    end

    attr_reader :jump_list, :jump_index

    # Special-mark hooks (Stage 5 fills these in).
    def previous_jump_position
      return nil if @jump_index <= 0

      @jump_list[@jump_index - 1]
    end

    def visual_position(name)
      return nil unless @last_visual

      name == '<' ? @last_visual[:anchor] : @last_visual[:last_end]
    end

    private def rvim_q_prefix(key)
      if @recording_macro
        name = @recording_macro
        @macros[name] = @macro_keys.dup
        @recording_macro = nil
        @macro_keys = []
        @status_message = "Recorded into @#{name}"
      else
        @waiting_proc = lambda do |reg_key, _sym|
          @waiting_proc = nil
          ch = reg_key.is_a?(Integer) ? reg_key.chr : reg_key.to_s
          if ch =~ /\A[a-z]\z/
            @recording_macro = ch
            @macro_keys = []
            @status_message = "Recording @#{ch}"
          end
        end
      end
    end

    private def rvim_at_prefix(key, arg: 1)
      count = arg
      @waiting_proc = lambda do |reg_key, _sym|
        @waiting_proc = nil
        ch = reg_key.is_a?(Integer) ? reg_key.chr : reg_key.to_s
        target = ch == '@' ? @last_macro_register : ch
        keys = @macros[target]
        next unless keys && !keys.empty?

        @last_macro_register = target
        @replaying = true
        saved_arg = @vi_arg
        @vi_arg = nil
        count.times { keys.each { |k| update(k) } }
        @vi_arg = saved_arg
        @replaying = false
      end
    end

    private def rvim_dot(key, arg: 1)
      return if @last_change_keys.empty?

      count = arg
      keys = @last_change_keys.dup
      @replaying = true
      @vi_arg = nil # don't double-apply the count to each replayed key
      count.times do
        keys.each { |k| update(k) }
      end
    ensure
      @replaying = false
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

    def write_register(text, kind, register: nil)
      name = register || '"'
      if name == '+'
        Rvim::SystemClipboard.write(text.is_a?(Array) ? text.join("\n") : text.to_s)
      end
      if name == '%'
        @status_message = 'E354: Invalid register name: %'
        return
      end
      @registers.write(name, text, kind)
    end

    def read_register(name = nil)
      n = name || '"'
      if n == '+'
        text = Rvim::SystemClipboard.read
        kind = text.end_with?("\n") ? :line : :char
        return Rvim::RegisterEntry.new(text.chomp, kind)
      end
      if n == '%'
        return Rvim::RegisterEntry.new(@filepath.to_s, :char)
      end
      @registers.read(n)
    end

    # Used by every operator (yank/delete/change) to record captured text.
    # Routes to @pending_register if set, else to the unnamed register, and
    # updates numbered registers ("0 on yank, "1-"9 ring on delete/change).
    def set_clipboard(content, kind, op: :yank)
      write_register(content, kind, register: @pending_register)
      case op
      when :yank
        @registers.write_yank_history(content, kind)
      when :delete, :change
        @registers.write_delete_history(content, kind)
      end
      consume_pending_register
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
      if target
        push_jump
        move_cursor_to(target[0], target[1])
      end
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
        push_jump
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
      if target
        push_jump
        move_cursor_to(target[0], target[1])
      end
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
      push_jump
      target = arg.is_a?(Integer) && arg > 0 ? arg - 1 : @buffer_of_lines.size - 1
      @line_index = target.clamp(0, @buffer_of_lines.size - 1)
      @byte_pointer = 0
    end

    private def vi_next_word(key, arg: 1)
      arg.times { advance_word_start(big: false) || break }
    end

    private def vi_next_big_word(key, arg: 1)
      arg.times { advance_word_start(big: true) || break }
    end

    private def vi_prev_word(key, arg: 1)
      arg.times { retreat_word_start(big: false) || break }
    end

    private def vi_prev_big_word(key, arg: 1)
      arg.times { retreat_word_start(big: true) || break }
    end

    private def vi_end_word(key, arg: 1, inclusive: false)
      arg.times { advance_word_end(big: false) || break }
    end

    private def vi_end_big_word(key, arg: 1, inclusive: false)
      arg.times { advance_word_end(big: true) || break }
    end

    private def word_class(byte, big)
      return :space if byte.nil? || byte == ' ' || byte == "\t"
      return :word if big

      byte =~ /\w/ ? :word : :punct
    end

    private def advance_word_start(big:)
      line = @buffer_of_lines[@line_index] || ''
      # Step over the current run.
      cur_class = @byte_pointer < line.bytesize ? word_class(line.byteslice(@byte_pointer, 1), big) : :space
      while @byte_pointer < line.bytesize && word_class(line.byteslice(@byte_pointer, 1), big) == cur_class && cur_class != :space
        @byte_pointer += 1
      end
      # Now skip whitespace (including line breaks) until we find a non-space.
      loop do
        line = @buffer_of_lines[@line_index] || ''
        while @byte_pointer < line.bytesize && word_class(line.byteslice(@byte_pointer, 1), big) == :space
          @byte_pointer += 1
        end
        return true if @byte_pointer < line.bytesize

        if @line_index + 1 < @buffer_of_lines.size
          @line_index += 1
          @byte_pointer = 0
          # Empty line counts as a word boundary — stop here.
          return true if (@buffer_of_lines[@line_index] || '').empty?
        else
          # At EOF: clamp to last char of last line.
          last = @buffer_of_lines[@line_index] || ''
          @byte_pointer = [last.bytesize - 1, 0].max
          return false
        end
      end
    end

    private def retreat_word_start(big:)
      # If at start of line, jump to end of previous line.
      if @byte_pointer.zero?
        return false if @line_index.zero?

        @line_index -= 1
        prev = @buffer_of_lines[@line_index] || ''
        @byte_pointer = prev.bytesize
      end
      # Step left past whitespace.
      line = @buffer_of_lines[@line_index] || ''
      while @byte_pointer > 0 && word_class(line.byteslice(@byte_pointer - 1, 1), big) == :space
        @byte_pointer -= 1
      end
      return retreat_word_start(big: big) if @byte_pointer.zero?

      # Now back up through the current word/punct run to its start.
      cls = word_class(line.byteslice(@byte_pointer - 1, 1), big)
      while @byte_pointer > 0 && word_class(line.byteslice(@byte_pointer - 1, 1), big) == cls
        @byte_pointer -= 1
      end
      true
    end

    private def advance_word_end(big:)
      line = @buffer_of_lines[@line_index] || ''
      # Step forward by one position to escape the current word-end.
      if @byte_pointer + 1 < line.bytesize
        @byte_pointer += 1
      elsif @line_index + 1 < @buffer_of_lines.size
        @line_index += 1
        @byte_pointer = 0
        line = @buffer_of_lines[@line_index] || ''
      else
        return false
      end
      # Skip whitespace (possibly across lines).
      loop do
        line = @buffer_of_lines[@line_index] || ''
        while @byte_pointer < line.bytesize && word_class(line.byteslice(@byte_pointer, 1), big) == :space
          @byte_pointer += 1
        end
        break if @byte_pointer < line.bytesize
        return false if @line_index + 1 >= @buffer_of_lines.size

        @line_index += 1
        @byte_pointer = 0
      end
      # Advance through the current word/punct run; stop on the last char.
      cls = word_class(line.byteslice(@byte_pointer, 1), big)
      while @byte_pointer + 1 < line.bytesize && word_class(line.byteslice(@byte_pointer + 1, 1), big) == cls
        @byte_pointer += 1
      end
      true
    end

    private def rvim_g_prefix(key)
      @waiting_proc = lambda do |key_for_proc, _sym|
        @waiting_proc = nil
        case key_for_proc
        when 'g', 'g'.ord
          push_jump
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
      capture_charwise(byte_pointer_diff, op: :delete)
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
      capture_charwise(byte_pointer_diff, op: :change)
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
      capture_charwise(byte_pointer_diff, op: :yank)
      super
    end

    private def capture_charwise(byte_pointer_diff, op: :yank)
      return if byte_pointer_diff.zero?

      if byte_pointer_diff > 0
        cut = current_line.byteslice(@byte_pointer, byte_pointer_diff)
      else
        cut = current_line.byteslice(@byte_pointer + byte_pointer_diff, -byte_pointer_diff)
      end
      set_clipboard(cut.to_s, :char, op: op)
    end

    private def delete_lines_linewise(count)
      return if @buffer_of_lines.empty?

      count = [count, @buffer_of_lines.size - @line_index].min
      cut_lines = @buffer_of_lines.slice!(@line_index, count) || []
      set_clipboard(cut_lines.join("\n"), :line, op: :delete)
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
      set_clipboard(text, :line, op: :yank)
    end

    private def change_lines_linewise(count)
      count = [count, @buffer_of_lines.size - @line_index].min
      cut_lines = @buffer_of_lines.slice!(@line_index, count) || []
      set_clipboard(cut_lines.join("\n"), :line, op: :change)
      @buffer_of_lines.insert(@line_index, String.new(encoding: encoding))
      @byte_pointer = 0
      @config.editing_mode = :vi_insert
    end

    private def rvim_paste_after(key, arg: 1)
      entry = read_register(@pending_register)
      consume_pending_register
      return vi_paste_next(key, arg: arg) unless entry

      case entry.kind
      when :line then paste_lines_after(entry.text)
      when :char then paste_char_after(entry.text)
      when :block then paste_block(entry.text, after: true)
      else vi_paste_next(key, arg: arg)
      end
    end

    private def rvim_paste_before(key, arg: 1)
      entry = read_register(@pending_register)
      consume_pending_register
      return vi_paste_prev(key, arg: arg) unless entry

      case entry.kind
      when :line then paste_lines_before(entry.text)
      when :char then paste_char_before(entry.text)
      when :block then paste_block(entry.text, after: false)
      else vi_paste_prev(key, arg: arg)
      end
    end

    private def paste_lines_after(content)
      return unless content

      content.to_s.split("\n", -1).each_with_index do |line, i|
        @buffer_of_lines.insert(@line_index + 1 + i, String.new(line, encoding: encoding))
      end
      @line_index += 1
      @byte_pointer = 0
    end

    private def paste_lines_before(content)
      return unless content

      content.to_s.split("\n", -1).each_with_index do |line, i|
        @buffer_of_lines.insert(@line_index + i, String.new(line, encoding: encoding))
      end
      @byte_pointer = 0
    end

    private def paste_char_after(content)
      return unless content

      lines = content.to_s.split("\n", -1)
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

    private def paste_char_before(content)
      return unless content

      @byte_pointer -= 1
      @byte_pointer = -1 if @byte_pointer.negative?
      paste_char_after(content)
    end

    private def paste_block(content, after:)
      return unless content

      base_line = @line_index
      base_col = @byte_pointer + (after ? 1 : 0)
      Array(content).each_with_index do |chunk, i|
        target_line = base_line + i
        @buffer_of_lines[target_line] ||= String.new('', encoding: encoding)
        line = @buffer_of_lines[target_line]
        col = [base_col, line.bytesize].min
        head = line.byteslice(0, col) || +''
        pad = col > line.bytesize ? ' ' * (col - line.bytesize) : ''
        tail = line.byteslice(col, line.bytesize - col) || +''
        @buffer_of_lines[target_line] = String.new(head + pad + chunk.to_s + tail, encoding: encoding)
      end
      @line_index = base_line
      @byte_pointer = base_col
    end

    def pending_register
      @pending_register
    end

    def consume_pending_register
      @pending_register = nil
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
      editor&.exit_code || 0
    end
  end
end
