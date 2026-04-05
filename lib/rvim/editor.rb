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
      @last_change_pos = nil
      @last_insert_pos = nil
      @last_yank_range = nil
      @jump_list = []
      @jump_index = 0
      @buffers = {}
      @buffer_order = []
      @next_buffer_id = 1
      @current_buffer = nil
      @windows = []
      @current_window = nil
      @split_orientation = nil
      @tabs = []
      @current_tab_index = 0
      @settings = Rvim::Settings.new
      @settings.editor = self
      @ex_history = []
      @history_cursor = nil
      @history_pending = nil
      @keymap = Rvim::Keymap.new
      @map_pending_keys = +''
      @map_recursion_depth = 0
      @map_noremap_active = false
      @let_vars = {}
      @folds = Rvim::Folds.new
      @completion_active = false
      @completion_candidates = []
      @completion_index = 0
      @completion_base = +''
      @completion_base_byte = 0
      @completion_line_index = 0
      @autocommands = Rvim::Autocommands.new
      @quickfix = Rvim::Quickfix.new
      install_key_bindings
    end

    attr_reader :autocommands, :quickfix

    attr_reader :folds

    attr_reader :let_vars

    def mapleader
      @let_vars['mapleader'] || '\\'
    end

    EX_HISTORY_MAX = 100

    attr_reader :ex_history

    attr_reader :keymap

    attr_reader :settings

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
      @config.add_default_key_binding_by_keymap(:vi_command, [0x06], :rvim_page_down)     # Ctrl-F
      @config.add_default_key_binding_by_keymap(:vi_command, [0x02], :rvim_page_up)       # Ctrl-B
      @config.add_default_key_binding_by_keymap(:vi_command, [0x01], :rvim_increment)     # Ctrl-A
      @config.add_default_key_binding_by_keymap(:vi_command, [0x18], :rvim_decrement)     # Ctrl-X
      @config.add_default_key_binding_by_keymap(:vi_command, [?z.ord], :rvim_fold_prefix)
      @config.add_default_key_binding_by_keymap(:vi_insert, [0x0E], :rvim_complete_next) # Ctrl-N
      @config.add_default_key_binding_by_keymap(:vi_insert, [0x10], :rvim_complete_prev) # Ctrl-P
      @config.add_default_key_binding_by_keymap(:vi_command, [?%.ord], :rvim_match_motion)
      @config.add_default_key_binding_by_keymap(:vi_command, [?(.ord], :rvim_sentence_backward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?).ord], :rvim_sentence_forward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?{.ord], :rvim_paragraph_backward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?}.ord], :rvim_paragraph_forward)
    end

    def open(path)
      is_new = path && !@buffers.values.find { |b| b.filepath == path }
      buf = find_or_create_buffer(path)
      swap_to_buffer(buf)
      if is_new
        Rvim::Modeline.apply(self, buf) if path
        load_persistent_undo(path) if path && @settings.get(:undofile)
        @autocommands&.fire(:bufread, path.to_s, self)
        ft = Rvim::Syntax.detect_language(path)
        @autocommands&.fire(:filetype, ft.to_s, self) if ft
      end
    end

    private def load_persistent_undo(path)
      data = Rvim::UndoFile.read(path)
      return unless data

      history, index = data
      return if history.nil? || history.empty?

      head_state = history[index] || history.last
      return unless head_state.is_a?(Array) && head_state[0] == @buffer_of_lines

      @undo_redo_history = history
      @undo_redo_index = index
      @current_buffer.undo_redo_history = history
      @current_buffer.undo_redo_index = index
    end

    SOURCE_MAX_DEPTH = 10

    def source(path, depth: 0)
      expanded = File.expand_path(path.to_s)
      unless File.exist?(expanded)
        @status_message = "E484: Can't open file #{path}"
        return false
      end
      if depth > SOURCE_MAX_DEPTH
        @status_message = "E22: Scripts nested too deep"
        return false
      end

      File.foreach(expanded) do |line|
        line = line.chomp
        next if line.strip.empty?
        next if line.lstrip.start_with?('"', '#')

        parsed = Rvim::Command.parse(line)
        next unless parsed

        if parsed.verb == :source || parsed.verb == :so
          source(parsed.arg.to_s, depth: depth + 1) unless parsed.arg.to_s.empty?
        else
          Rvim::Command.execute(self, parsed)
        end
      end
      true
    rescue => e
      @status_message = "E: source #{path}: #{e.message}"
      false
    end

    private def find_or_create_buffer(path)
      existing = @buffers.values.find { |b| b.filepath == path } if path
      return existing if existing

      buf = Rvim::Buffer.new(@next_buffer_id, path, encoding: encoding)
      @next_buffer_id += 1
      @buffers[buf.id] = buf
      @buffer_order << buf.id

      ft = Rvim::Syntax.detect_language(path)
      Rvim::FileType.run(ft, buf, self) if ft

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
      @folds = buf.folds
      ensure_current_window(buf)
      @autocommands&.fire(:bufenter, buf.filepath.to_s, self)
    end

    private def ensure_current_window(buf)
      if @windows.empty?
        win = Rvim::Window.new(buf)
        @windows << win
        @current_window = win
      else
        @current_window.buffer = buf if @current_window
      end
      ensure_current_tab
    end

    private def ensure_current_tab
      return unless @tabs.empty? && @current_window

      tab = Rvim::Tab.new(@current_window)
      tab.windows = @windows
      tab.split_orientation = @split_orientation
      @tabs << tab
      @current_tab_index = 0
    end

    attr_reader :tabs, :current_tab_index

    def current_tab
      @tabs[@current_tab_index]
    end

    def swap_to_tab(idx)
      return if idx < 0 || idx >= @tabs.size || idx == @current_tab_index

      save_current_tab_state
      @current_tab_index = idx
      load_current_tab_state
    end

    private def save_current_tab_state
      tab = @tabs[@current_tab_index]
      return unless tab

      tab.windows = @windows
      tab.current_window = @current_window
      tab.split_orientation = @split_orientation
    end

    private def load_current_tab_state
      tab = @tabs[@current_tab_index]
      return unless tab

      @windows = tab.windows
      @current_window = tab.current_window
      @split_orientation = tab.split_orientation
      activate_window(@current_window) if @current_window
    end

    attr_reader :windows, :current_window, :split_orientation, :list_view

    def show_list(lines)
      @list_view = Rvim::ListView.new(lines.compact)
      @prompt_mode = :listing
    end

    def dismiss_list
      @list_view = nil
      @prompt_mode = nil
    end

    def list_rows
      base = @screen ? @screen.list_overlay_rows : 6
      [base, 4].max
    end

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
        when '+' then resize_current(:height, +1)
        when '-' then resize_current(:height, -1)
        when '>' then resize_current(:width, +1)
        when '<' then resize_current(:width, -1)
        when '=' then equalize_windows
        end
      end
    end

    def resize_current(axis, delta)
      return if @windows.size < 2

      attr = axis == :height ? :extra_rows : :extra_cols
      cur = @current_window
      idx = @windows.index(cur) || 0
      neighbor = @windows[idx + 1] || @windows[idx - 1]
      return unless neighbor

      cur.send("#{attr}=", cur.send(attr) + delta)
      neighbor.send("#{attr}=", neighbor.send(attr) - delta)
    end

    def equalize_windows
      @windows.each do |w|
        w.extra_rows = 0
        w.extra_cols = 0
      end
    end

    def resize_to(axis, target)
      return if @windows.size < 2

      attr = axis == :height ? :extra_rows : :extra_cols
      total = axis == :height ? content_rows_total : @cols_for_resize
      total ||= @windows.sum { |w| axis == :height ? w.height : w.width }
      baseline = total / @windows.size
      delta = target - baseline
      cur = @current_window
      neighbor = @windows[(@windows.index(cur) || 0) + 1] || @windows[(@windows.index(cur) || 0) - 1]
      return unless neighbor

      old_extra = cur.send(attr)
      cur.send("#{attr}=", delta)
      neighbor.send("#{attr}=", neighbor.send(attr) - (delta - old_extra))
    end

    private def content_rows_total
      return nil unless @screen

      @screen.respond_to?(:rows) ? (@screen.rows - 1) : nil
    end

    private def rvim_page_down(key, arg: 1)
      page_jump(+1, arg)
    end

    private def rvim_page_up(key, arg: 1)
      page_jump(-1, arg)
    end

    private def rvim_complete_next(key, arg: 1)
      step_completion(+1)
    end

    private def rvim_complete_prev(key, arg: 1)
      step_completion(-1)
    end

    private def step_completion(delta)
      if @completion_active
        return if @completion_candidates.empty?

        @completion_index = (@completion_index + delta) % @completion_candidates.size
        replace_completion_with(@completion_candidates[@completion_index])
        update_completion_status
      else
        start_completion(delta)
      end
    end

    private def start_completion(delta)
      line = @buffer_of_lines[@line_index] || ''
      base = Rvim::Completion.base_at(line, @byte_pointer)
      candidates = Rvim::Completion.candidates(@buffer_of_lines, base)
      if candidates.empty?
        @status_message = 'Pattern not found'
        return
      end

      @completion_active = true
      @completion_candidates = candidates
      @completion_index = delta < 0 ? candidates.size - 1 : 0
      @completion_base = base
      @completion_base_byte = Rvim::Completion.base_start(line, @byte_pointer)
      @completion_line_index = @line_index
      replace_completion_with(@completion_candidates[@completion_index])
      update_completion_status
    end

    private def replace_completion_with(word)
      line = @buffer_of_lines[@completion_line_index] || ''
      head = line.byteslice(0, @completion_base_byte) || +''
      # Compute current end of the inserted word: head + previously inserted portion.
      # We know the previously inserted span was the most-recent candidate or the
      # original base. byte_pointer should point at end of that span.
      tail = line.byteslice(@byte_pointer, line.bytesize - @byte_pointer) || +''
      new_line = String.new(head + word + tail, encoding: encoding)
      @buffer_of_lines[@completion_line_index] = new_line
      @byte_pointer = (head + word).bytesize
      @modified = true
    end

    private def update_completion_status
      n = @completion_index + 1
      total = @completion_candidates.size
      @status_message = "match #{n} of #{total}: #{@completion_candidates[@completion_index]}"
    end

    private def cancel_completion
      @completion_active = false
      @completion_candidates = []
      @completion_index = 0
      @completion_base = +''
      @completion_base_byte = 0
      @completion_line_index = 0
    end

    private def completion_key?(key)
      sym = key.method_symbol
      sym == :rvim_complete_next || sym == :rvim_complete_prev
    end

    attr_reader :completion_active, :completion_candidates, :completion_index

    private def rvim_match_motion(key, arg: 1)
      target = Rvim::MatchMotion.match_at(@buffer_of_lines, @line_index, @byte_pointer)
      return unless target

      push_jump
      @line_index, @byte_pointer = target
    end

    private def rvim_sentence_forward(key, arg: 1)
      arg.times do
        target = Rvim::TextMotion.next_sentence(@buffer_of_lines, @line_index, @byte_pointer)
        break unless target

        push_jump
        @line_index, @byte_pointer = target
      end
    end

    private def rvim_sentence_backward(key, arg: 1)
      arg.times do
        target = Rvim::TextMotion.prev_sentence(@buffer_of_lines, @line_index, @byte_pointer)
        break unless target

        push_jump
        @line_index, @byte_pointer = target
      end
    end

    private def rvim_paragraph_forward(key, arg: 1)
      arg.times do
        target_line = Rvim::TextMotion.next_paragraph(@buffer_of_lines, @line_index)
        break if target_line == @line_index

        push_jump
        @line_index = target_line
        @byte_pointer = 0
      end
    end

    private def rvim_paragraph_backward(key, arg: 1)
      arg.times do
        target_line = Rvim::TextMotion.prev_paragraph(@buffer_of_lines, @line_index)
        break if target_line == @line_index

        push_jump
        @line_index = target_line
        @byte_pointer = 0
      end
    end

    private def goto_definition
      word = word_at_cursor
      return unless word

      pattern = "\\b#{Regexp.escape(word)}\\b"
      matches = Rvim::Search.scan(@buffer_of_lines, pattern, ignorecase: false)
      return if matches.empty?

      first = matches.first
      target_line, target_byte = first[0], first[1]
      return if target_line == @line_index && target_byte == @byte_pointer

      push_jump
      @line_index = target_line
      @byte_pointer = target_byte
    end

    private def rvim_increment(key, arg: 1)
      modify_number_at_cursor(+arg)
    end

    private def rvim_decrement(key, arg: 1)
      modify_number_at_cursor(-arg)
    end

    private def rvim_fold_prefix(key, arg: nil)
      count = arg
      @waiting_proc = lambda do |k, _sym|
        @waiting_proc = nil
        ch = k.is_a?(Integer) ? k.chr : k.to_s
        case ch
        when 'f' then create_fold_at_cursor(count || 1)
        when 'd' then @folds.remove(@line_index)
        when 'E' then @folds.clear
        when 'o' then @folds.open(@line_index)
        when 'c' then @folds.close(@line_index)
        when 'a' then @folds.toggle(@line_index)
        when 'M' then @folds.close_all
        when 'R' then @folds.open_all
        when 'z' then viewport_scroll_to(:center)
        when 't' then viewport_scroll_to(:top)
        when 'b' then viewport_scroll_to(:bottom)
        when 'j' then jump_to_fold(:next)
        when 'k' then jump_to_fold(:prev)
        when 'n' then @settings.set(:foldenable, false)
        when 'N' then @settings.set(:foldenable, true)
        when 'i' then @settings.set(:foldenable, !@settings.get(:foldenable))
        end
      end
    end

    def jump_to_fold(direction)
      collected = []
      @folds.each { |f| collected << f }
      sorted = collected.sort_by(&:start_line)
      target = if direction == :next
                 sorted.find { |f| f.start_line > @line_index }
               else
                 sorted.reverse.find { |f| f.start_line < @line_index }
               end
      return unless target

      push_jump
      @line_index = target.start_line
      @byte_pointer = 0
    end

    def rebuild_folds_for_method
      method = @settings.get(:foldmethod).to_s
      case method
      when 'marker'
        @folds.clear
        Rvim::Folds.from_markers(@buffer_of_lines).each do |s, e|
          @folds.add(s, e, closed: true)
        end
      end
    end

    def viewport_scroll_to(position)
      win = @current_window
      return unless win

      content_rows = [win.height - 1, 1].max
      cl = @line_index
      win.scroll_top = case position
                       when :center then [cl - (content_rows / 2), 0].max
                       when :top then cl
                       when :bottom then [cl - content_rows + 1, 0].max
                       end
    end

    def create_fold_at_cursor(line_count)
      start_line = @line_index
      end_line = [start_line + line_count - 1, @buffer_of_lines.size - 1].min
      return if end_line < start_line

      @folds.add(start_line, end_line, closed: true)
    end

    def create_fold_over(start_line, end_line)
      lo = [start_line, end_line].min.clamp(0, @buffer_of_lines.size - 1)
      hi = [start_line, end_line].max.clamp(0, @buffer_of_lines.size - 1)
      @folds.add(lo, hi, closed: true)
    end

    private def modify_number_at_cursor(delta)
      line = @buffer_of_lines[@line_index] || ''
      return if line.empty?

      start = [@byte_pointer, line.bytesize - 1].min
      if line.byteslice(start, 1) !~ /\d/
        pos = start + 1
        pos += 1 while pos < line.bytesize && line.byteslice(pos, 1) !~ /\d/
        return if pos >= line.bytesize

        start = pos
      else
        start -= 1 while start > 0 && line.byteslice(start - 1, 1) =~ /\d/
      end

      ending = start
      ending += 1 while ending < line.bytesize && line.byteslice(ending, 1) =~ /\d/

      has_minus = false
      if start > 0 && line.byteslice(start - 1, 1) == '-'
        has_minus = start == 1 || line.byteslice(start - 2, 1) !~ /\w/
      end
      num_start = has_minus ? start - 1 : start

      digits = line.byteslice(num_start, ending - num_start)
      new_value = digits.to_i + delta
      new_text = new_value.to_s

      before = line.byteslice(0, num_start)
      after = line.byteslice(ending, line.bytesize - ending)
      @buffer_of_lines[@line_index] = String.new(before + new_text + after, encoding: encoding)
      @byte_pointer = (before + new_text).bytesize - 1
      @modified = true
    end

    private def page_jump(direction, count)
      win = @current_window
      return unless win

      content_rows = [win.height - 1, 1].max # status row at bottom of window
      page = [content_rows - 2, 1].max # leave 2 rows of context like vim
      delta = page * count * direction
      target = (@line_index + delta).clamp(0, [@buffer_of_lines.size - 1, 0].max)
      return if target == @line_index

      push_jump
      @line_index = target
      target_line = @buffer_of_lines[@line_index] || ''
      @byte_pointer = first_non_whitespace_col(target_line).clamp(0, target_line.bytesize)

      # Position the destination line per vim convention:
      # - Ctrl-F (forward): new cursor line is at the TOP of the new page
      # - Ctrl-B (backward): new cursor line is at the BOTTOM of the new page
      if direction.positive?
        win.scroll_top = target
      else
        win.scroll_top = [target - content_rows + 1, 0].max
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
      @folds = buf.folds
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
      @current_buffer.folds = @folds
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

    def replace_line_range(start_line, end_line, new_lines)
      return if @buffer_of_lines.empty?

      lo = start_line.clamp(0, @buffer_of_lines.size - 1)
      hi = end_line.clamp(0, @buffer_of_lines.size - 1)
      replacement = new_lines.map { |l| String.new(l, encoding: encoding) }
      @buffer_of_lines[lo..hi] = replacement
      @line_index = lo.clamp(0, [@buffer_of_lines.size - 1, 0].max)
      @byte_pointer = 0
      @modified = true
      @folds&.shift_after(lo, replacement.size - (hi - lo + 1))
    end

    def insert_lines_after(line_index, new_lines)
      return if new_lines.empty?

      idx = line_index.clamp(-1, @buffer_of_lines.size - 1)
      additions = new_lines.map { |l| String.new(l, encoding: encoding) }
      @buffer_of_lines.insert(idx + 1, *additions)
      @line_index = idx + 1
      @byte_pointer = 0
      @modified = true
      @folds&.shift_after(idx, additions.size)
    end

    def save(path = nil)
      target = path || @filepath
      raise 'no file path' unless target

      @autocommands&.fire(:bufwritepre, target.to_s, self)
      content = @buffer_of_lines.join("\n")
      content += "\n" unless content.end_with?("\n")
      File.write(target, content)
      @filepath = target
      @modified = false
      Rvim::UndoFile.write(target, @undo_redo_history, @undo_redo_index) if @settings.get(:undofile)
      @autocommands&.fire(:bufwritepost, target.to_s, self)
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
      if @prompt_mode == :listing
        process_listing_key(key)
        return
      end

      if @completion_active && !completion_key?(key)
        cancel_completion
      end

      if @rvim_pending_case_op
        return if dispatch_case_pending(key)

        # Motion path: dispatch the key normally and apply the op to the delta.
        pre = [@line_index, @byte_pointer]
        saved_kind = @rvim_pending_case_op
        inclusive = inclusive_motion_key?(key)
        clear_case_pending
        super
        post = [@line_index, @byte_pointer]
        apply_case_motion(saved_kind, pre, post, inclusive: inclusive)
        return
      end

      if mapping_eligible?
        decision = route_through_mappings(key)
        return if decision == :consumed
      end

      pre_idle = idle_for_recording?
      pre_buffer = @buffer_of_lines.map(&:dup)
      pre_mode = editing_mode_label
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

      capture_special_marks(pre_buffer, pre_mode)
      freeze_change_if_settled(pre_buffer) unless @replaying
    end

    MAXMAPDEPTH = 1000

    private def mapping_eligible?
      return false if @map_noremap_active
      return false if @replaying
      return false if @prompt_mode
      return false if @list_view
      return false if @waiting_proc
      return false if @rvim_text_object_pending
      return false if @rvim_visual_textobj_pending

      true
    end

    private def route_through_mappings(key)
      ch = key.char
      return :fall_through unless ch.is_a?(String) && ch.bytesize >= 1

      mode = current_mapping_mode
      return :fall_through if mode.nil?

      candidate = @map_pending_keys + ch
      result, mapping = @keymap.lookup(mode, candidate)

      case result
      when :exact
        @map_pending_keys = +''
        expand_mapping(mapping)
        :consumed
      when :prefix
        @map_pending_keys = candidate
        :consumed
      else
        if @map_pending_keys.empty?
          :fall_through
        else
          flush_pending_with(ch)
          :consumed
        end
      end
    end

    private def current_mapping_mode
      return :visual if @visual_mode
      return :op_pending if operator_pending?
      return :insert if editing_mode_label == :vi_insert

      :normal
    end

    private def flush_pending_with(current_char)
      sequence = @map_pending_keys + current_char
      @map_pending_keys = +''
      @map_noremap_active = true
      begin
        sequence.each_char do |c|
          dispatch_synthesized_key(c)
        end
      ensure
        @map_noremap_active = false
      end
    end

    private def expand_mapping(mapping)
      @map_recursion_depth += 1
      if @map_recursion_depth > MAXMAPDEPTH
        @status_message = 'E223: recursive mapping'
        @map_recursion_depth = 0
        @map_pending_keys = +''
        return
      end

      begin
        if mapping.recursive
          mapping.rhs.each_char { |c| dispatch_synthesized_key(c) }
        else
          @map_noremap_active = true
          begin
            mapping.rhs.each_char { |c| dispatch_synthesized_key(c) }
          ensure
            @map_noremap_active = false
          end
        end
      ensure
        @map_recursion_depth -= 1
      end
    end

    private def dispatch_synthesized_key(ch)
      key = synthesize_key(ch)
      update(key)
    end

    private def synthesize_key(ch)
      sym = nil
      bytes = ch.bytes
      if bytes.size == 1
        result = @config.key_bindings.get(bytes)
        sym = case result
              when Symbol then result
              when Array then result.first
              end
      end
      Reline::Key.new(ch, sym, false)
    end

    private def capture_special_marks(pre_buffer, pre_mode)
      if pre_buffer != @buffer_of_lines
        @last_change_pos = [@line_index, @byte_pointer]
      end
      cur_mode = editing_mode_label
      if pre_mode == :vi_insert && cur_mode == :vi_command
        @last_insert_pos = [@line_index, @byte_pointer]
        @autocommands&.fire(:insertleave, @filepath.to_s, self)
      elsif pre_mode == :vi_command && cur_mode == :vi_insert
        @autocommands&.fire(:insertenter, @filepath.to_s, self)
      end
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

    attr_reader :last_change_pos, :last_insert_pos

    def last_yank_range_start
      @last_yank_range&.dig(:start)
    end

    def last_yank_range_end
      @last_yank_range&.dig(:end)
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
      when 'u'
        sel = selection
        if sel
          Rvim::Operations.lowercase(self, sel)
          @modified = true
        end
        exit_visual
        return true
      when 'U'
        sel = selection
        if sel
          Rvim::Operations.uppercase(self, sel)
          @modified = true
        end
        exit_visual
        return true
      when 'z'
        sel = selection
        exit_visual
        if sel
          start_line = sel.start_line
          end_line = sel.end_line
          @waiting_proc = lambda do |k, _sym|
            @waiting_proc = nil
            ch2 = k.is_a?(Integer) ? k.chr : k.to_s
            create_fold_over(start_line, end_line) if ch2 == 'f'
          end
        end
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
    # Also records the last yank/change region for the '[' and ']' marks.
    def set_clipboard(content, kind, op: :yank)
      write_register(content, kind, register: @pending_register)
      case op
      when :yank
        @registers.write_yank_history(content, kind)
      when :delete, :change
        @registers.write_delete_history(content, kind)
      end
      # Record region: cursor at this point is the start of the affected area
      # (operators move the cursor to the start). We approximate end with the
      # same point — refined when we have explicit region tracking.
      @last_yank_range = {
        start: [@line_index, @byte_pointer],
        end: [@line_index, @byte_pointer],
      }
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

    private def process_listing_key(key)
      ch = key.char
      case ch
      when ' ', "\r", "\n", 'f', "\x06"
        if @list_view.more?(list_rows)
          @list_view.advance!(list_rows)
        else
          dismiss_list
        end
      when 'q', "\e", "\x03"
        dismiss_list
      else
        # Any other key dismisses the list and re-dispatches to normal handling.
        dismiss_list
        update(key)
      end
    end

    private def process_prompt_key(key)
      ch = key.char
      if ch.nil?
        cancel_prompt
        return
      end

      if ch.is_a?(String) && ch.bytesize > 1 && ch.start_with?("\e")
        handle_prompt_escape_sequence(key)
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
        clear_history_cursor
      else
        @prompt_buffer << ch.to_s
        clear_history_cursor
      end
      refresh_incremental_search
    end

    private def handle_prompt_escape_sequence(key)
      return unless @prompt_mode == :ex

      case key.method_symbol
      when :ed_prev_history
        history_recall(-1)
      when :ed_next_history
        history_recall(+1)
      end
    end

    private def history_recall(direction)
      return if @ex_history.empty?

      if @history_cursor.nil?
        @history_pending = @prompt_buffer.dup
        @history_cursor = direction < 0 ? @ex_history.size - 1 : 0
      else
        @history_cursor += direction
      end

      if @history_cursor < 0
        @history_cursor = 0
      elsif @history_cursor >= @ex_history.size
        # Stepped past newest — restore the in-progress draft
        @history_cursor = nil
        @prompt_buffer = (@history_pending || +'').dup
        @history_pending = nil
        return
      end

      @prompt_buffer = @ex_history[@history_cursor].dup
    end

    private def clear_history_cursor
      @history_cursor = nil
      @history_pending = nil
    end

    private def push_ex_history(line)
      return if line.nil? || line.strip.empty?
      return if @ex_history.last == line

      @ex_history << line
      @ex_history.shift while @ex_history.size > EX_HISTORY_MAX
    end

    private def refresh_incremental_search
      return unless @prompt_mode == :search_forward || @prompt_mode == :search_backward

      @search_matches = scan_pattern(@prompt_buffer)
    end

    private def scan_pattern(pattern_str)
      Rvim::Search.scan(@buffer_of_lines, pattern_str, ignorecase: ignorecase_for(pattern_str))
    end

    private def ignorecase_for(pattern_str)
      Rvim::Search.effective_ignorecase(
        pattern_str,
        ignorecase: @settings.get(:ignorecase),
        smartcase: @settings.get(:smartcase),
      )
    end

    private def execute_prompt
      case @prompt_mode
      when :ex
        push_ex_history(@prompt_buffer.dup)
        clear_history_cursor
        parsed = Rvim::Command.parse(@prompt_buffer)
        @prompt_mode = nil
        @prompt_buffer = +''
        Rvim::Command.execute(self, parsed) if parsed
      when :search_forward, :search_backward
        commit_search
      else
        reset_prompt
      end
    end

    private def cancel_prompt
      was_search = @prompt_mode == :search_forward || @prompt_mode == :search_backward
      reset_prompt
      clear_history_cursor
      @status_message = nil
      # Clear the incremental highlight if we cancel mid-search; preserve any
      # previously committed @search_pattern by re-scanning for it.
      if was_search
        @search_matches = @search_pattern ? scan_pattern(@search_pattern) : []
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
      clear_history_cursor
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
      matches = scan_pattern(pattern)
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

      @search_matches = scan_pattern(@search_pattern) if @search_matches.empty?
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

      matches = scan_pattern(pattern)
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
        skip_into_fold(:up)
        calculate_nearest_cursor(cursor)
      end
    end

    private def ed_next_history(key, arg: 1)
      arg.times do
        break if @line_index >= @buffer_of_lines.size - 1

        cursor = current_byte_pointer_cursor
        @line_index += 1
        skip_into_fold(:down)
        calculate_nearest_cursor(cursor)
      end
    end

    private def vi_to_history_line(key, arg: nil)
      push_jump
      target = arg.is_a?(Integer) && arg > 0 ? arg - 1 : @buffer_of_lines.size - 1
      @line_index = target.clamp(0, @buffer_of_lines.size - 1)
      snap_to_visible
      @byte_pointer = 0
    end

    private def skip_into_fold(direction)
      f = @folds.at_line(@line_index)
      return unless f && f.closed && @line_index != f.start_line

      if direction == :down
        @line_index = [f.end_line + 1, @buffer_of_lines.size - 1].min
        # If end_line+1 itself lands in another closed fold, snap to that fold's start
        snap_to_visible
      else
        @line_index = f.start_line
      end
    end

    private def snap_to_visible
      f = @folds.at_line(@line_index)
      return unless f && f.closed && @line_index != f.start_line

      @line_index = f.start_line
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

    private def rvim_g_prefix(key, arg: nil)
      saved_arg = arg
      @waiting_proc = lambda do |key_for_proc, _sym|
        @waiting_proc = nil
        case key_for_proc
        when 'g', 'g'.ord
          push_jump
          @line_index = 0
          @byte_pointer = 0
        when 'v', 'v'.ord
          reselect_last_visual
        when 't', 't'.ord
          tab_advance(saved_arg)
        when 'T', 'T'.ord
          tab_retreat(saved_arg)
        when 'n', 'n'.ord
          select_next_search_match(:forward)
        when 'N', 'N'.ord
          select_next_search_match(:backward)
        when 'u', 'u'.ord
          start_case_op(:lowercase, saved_arg)
        when 'U', 'U'.ord
          start_case_op(:uppercase, saved_arg)
        when '~', '~'.ord
          start_case_op(:toggle, saved_arg)
        when 'd', 'd'.ord
          goto_definition
        end
      end
    end

    private def start_case_op(kind, count_arg)
      @rvim_pending_case_op = kind
      @rvim_case_count = (count_arg.is_a?(Integer) && count_arg > 0) ? count_arg : 1
      @rvim_case_textobj_pending = nil
    end

    private def clear_case_pending
      @rvim_pending_case_op = nil
      @rvim_case_count = nil
      @rvim_case_textobj_pending = nil
    end

    private def case_pending_letter
      case @rvim_pending_case_op
      when :lowercase then 'u'
      when :uppercase then 'U'
      when :toggle then '~'
      end
    end

    # Returns true if the key was fully handled (linewise / text-object).
    # False means it should be treated as a motion: the caller dispatches
    # via super and applies the case op to the cursor delta.
    private def dispatch_case_pending(key)
      ch = key.char
      kind = @rvim_pending_case_op

      if @rvim_case_textobj_pending
        inclusive = @rvim_case_textobj_pending == :around
        range = Rvim::TextObject.find(ch, self, inclusive: inclusive)
        apply_case_to_range(kind, range) if range
        clear_case_pending
        return true
      end

      if ch == case_pending_letter
        count = @rvim_case_count || 1
        apply_linewise_case(kind, count)
        clear_case_pending
        return true
      end

      if ch == 'i' || ch == 'a'
        @rvim_case_textobj_pending = (ch == 'a' ? :around : :inner)
        return true
      end

      false
    end

    private def apply_linewise_case(kind, count)
      end_line = [@line_index + count - 1, @buffer_of_lines.size - 1].min
      sel = Rvim::Selection.from(:line, [@line_index, 0], [end_line, 0], @buffer_of_lines)
      apply_case_to_range(kind, sel)
    end

    INCLUSIVE_MOTION_CHARS = %w[$ e E f F t T].freeze

    private def inclusive_motion_key?(key)
      INCLUSIVE_MOTION_CHARS.include?(key.char)
    end

    private def apply_case_motion(kind, pre, post, inclusive: false)
      return if pre == post

      forward = (pre <=> post) <= 0
      start_pos, end_pos = forward ? [pre, post] : [post, pre]
      # Forward motions are exclusive of the endpoint by default (matches `dw`):
      # pull `end_pos` back one byte. Inclusive motions (`$`, `e`, `f`, `t`)
      # keep the endpoint.
      if forward && !inclusive
        end_pos = predecessor_position(end_pos)
      end
      return if end_pos.nil? || (start_pos <=> end_pos) > 0

      sel = Rvim::Selection.from(:char, start_pos, end_pos, @buffer_of_lines)
      apply_case_to_range(kind, sel) if sel
    end

    private def predecessor_position(pos)
      li, bp = pos
      if bp > 0
        [li, bp - 1]
      elsif li > 0
        prev_len = (@buffer_of_lines[li - 1] || '').bytesize
        [li - 1, [prev_len - 1, 0].max]
      else
        nil
      end
    end

    private def apply_case_to_range(kind, sel)
      return unless sel

      case kind
      when :lowercase then Rvim::Operations.lowercase(self, sel)
      when :uppercase then Rvim::Operations.uppercase(self, sel)
      when :toggle then Rvim::Operations.toggle_case(self, sel)
      end
      @modified = true
    end

    def select_next_search_match(direction)
      return unless @search_pattern && !@search_matches.empty?

      target = Rvim::Search.next_match(@search_matches, @line_index, @byte_pointer, direction)
      return unless target

      line, byte_start, byte_end = target
      push_jump
      @visual_mode = :char
      @visual_anchor = [line, byte_start]
      move_cursor_to(line, byte_end)
    end

    def tab_new(path = nil)
      buf = if path && !path.empty?
              find_or_create_buffer(path)
            else
              create_empty_buffer
            end
      win = Rvim::Window.new(buf)
      tab = Rvim::Tab.new(win)

      save_current_tab_state
      @tabs.insert(@current_tab_index + 1, tab)
      @current_tab_index += 1
      @windows = tab.windows
      @current_window = win
      @split_orientation = nil
      activate_window(win)
    end

    private def create_empty_buffer
      buf = Rvim::Buffer.new(@next_buffer_id, nil, encoding: encoding)
      @next_buffer_id += 1
      @buffers[buf.id] = buf
      @buffer_order << buf.id
      buf
    end

    def tab_move(target)
      return if @tabs.size <= 1

      src = @current_tab_index
      dst = target.clamp(0, @tabs.size - 1)
      return if src == dst

      save_current_tab_state
      tab = @tabs.delete_at(src)
      @tabs.insert(dst, tab)
      @current_tab_index = dst
      load_current_tab_state
    end

    def tab_close
      if @tabs.size <= 1
        @status_message = 'E784: Cannot close last tab page'
        return
      end

      save_current_tab_state
      @tabs.delete_at(@current_tab_index)
      @current_tab_index = [@current_tab_index, @tabs.size - 1].min.clamp(0, @tabs.size - 1)
      load_current_tab_state
    end

    def tab_only
      return if @tabs.size <= 1

      save_current_tab_state
      keeper = @tabs[@current_tab_index]
      @tabs = [keeper]
      @current_tab_index = 0
      load_current_tab_state
    end

    def tab_advance(arg = nil)
      return if @tabs.size < 2

      target = if arg.is_a?(Integer) && arg > 0
                 (arg - 1).clamp(0, @tabs.size - 1)
               else
                 (@current_tab_index + 1) % @tabs.size
               end
      swap_to_tab(target)
    end

    def tab_retreat(arg = nil)
      return if @tabs.size < 2

      target = if arg.is_a?(Integer) && arg > 0
                 (@current_tab_index - arg) % @tabs.size
               else
                 (@current_tab_index - 1) % @tabs.size
               end
      swap_to_tab(target)
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

    RVIMRC_PATH = '~/.rvimrc'

    def self.init_vim_path
      base = ENV['XDG_CONFIG_HOME']
      base = File.expand_path('~/.config') if base.nil? || base.empty?
      File.join(base, 'rvim', 'init.vim')
    end

    def self.start(*filepaths, norc: false)
      editor = new(Reline.core.config)
      filepaths = filepaths.flatten.compact
      filepaths.each { |path| editor.open(path) }
      unless norc
        [File.expand_path(RVIMRC_PATH), init_vim_path].each do |rc|
          editor.source(rc) if File.exist?(rc)
        end
      end
      editor.autocommands.fire(:vimenter, '*', editor)
      # Land on the first file the user passed, mirroring vim's `vim a b c`
      # behavior of opening all into the buffer list with the first active.
      if (first = filepaths.first) && (buf = editor.buffers.values.find { |b| b.filepath == first })
        editor.swap_to_buffer(buf)
      end
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
