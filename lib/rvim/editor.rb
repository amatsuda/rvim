# frozen_string_literal: true

require 'reline'
require 'fileutils'

module Rvim
  class Editor < Reline::LineEditor
    attr_reader :filepath, :visual_mode, :visual_anchor, :prompt_mode, :prompt_buffer
    attr_accessor :modified
    attr_reader :status_message, :messages

    MESSAGES_MAX = 200

    def status_message=(msg)
      @status_message = msg
      return if msg.nil? || msg.to_s.empty?

      @messages ||= []
      @messages << msg.to_s
      @messages.shift while @messages.size > MESSAGES_MAX
      @redir_sink&.<<(msg.to_s)
    end

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
      @messages = []
      @redir_sink = nil
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
      @abbreviations = Rvim::Abbreviations.new
      @user_commands = {}
      @block_insert_state = nil
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
      @completion_popup = nil
      @hover_popup = nil
      @signature_popup = nil
      @last_code_actions = nil
      @cmdline_popup = nil
      @cmdline_completion_context = nil
      @digraph_pending = false
      @digraph_chars = +''
      @completion_chain_pending = false
      @tag_stack = []
      @tag_matches = []
      @tag_match_index = 0
      @last_bang_cmd = nil
      @arg_list = []
      @arg_index = 0
      @alternate_filepath = nil
      @rvim_pending_format_op = false
      @rvim_pending_filter_op = false
      @rvim_pending_equal_op = false
      @rvim_pending_op = nil # :delete / :change / :yank
      @rvim_pending_op_count = 1
      @confirm_question = nil
      @confirm_options = nil
      @confirm_callback = nil
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

    attr_reader :abbreviations

    attr_reader :user_commands

    attr_reader :block_insert_state

    def lua
      @lua ||= Rvim::Lua::Runtime.new(self)
    end

    def lsp
      @lsp ||= Rvim::Lsp::Manager.new(self)
    end

    def cwd
      Dir.pwd
    end

    def pump_lua_loop
      sched = @lua_scheduler
      sched&.pump || 0
    end

    # Re-sync Lua's package.path with the current &runtimepath. Called by
    # Settings#set when the user (or a plugin) mutates :runtimepath.
    def lua_loader_refresh
      return unless @lua && @lua.available? && @lua.state

      Rvim::Lua::Loader.refresh(@lua.state, self)
    end

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
      @config.add_default_key_binding_by_keymap(:vi_insert, [0x0B], :rvim_digraph_start) # Ctrl-K
      @config.add_default_key_binding_by_keymap(:vi_insert, [0x09], :rvim_insert_tab)    # Tab
      @config.add_default_key_binding_by_keymap(:vi_insert, [0x18], :rvim_completion_chain) # Ctrl-X
      @config.add_default_key_binding_by_keymap(:vi_insert, [0x0D], :rvim_insert_newline)   # Enter
      @config.add_default_key_binding_by_keymap(:vi_command, [?%.ord], :rvim_match_motion)
      @config.add_default_key_binding_by_keymap(:vi_command, [?[.ord], :rvim_bracket_left)
      @config.add_default_key_binding_by_keymap(:vi_command, [?].ord], :rvim_bracket_right)
      @config.add_default_key_binding_by_keymap(:vi_command, [0x1D], :rvim_tag_jump)   # Ctrl-]
      @config.add_default_key_binding_by_keymap(:vi_command, [0x14], :rvim_tag_pop)    # Ctrl-T
      @config.add_default_key_binding_by_keymap(:vi_command, [?!.ord], :rvim_filter_operator)
      @config.add_default_key_binding_by_keymap(:vi_command, [?K.ord], :rvim_keyword_lookup)
      @config.add_default_key_binding_by_keymap(:vi_command, [?~.ord], :rvim_tilde)
      @config.add_default_key_binding_by_keymap(:vi_command, [?=.ord], :rvim_equal_operator)
      @config.add_default_key_binding_by_keymap(:vi_command, [?(.ord], :rvim_sentence_backward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?).ord], :rvim_sentence_forward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?{.ord], :rvim_paragraph_backward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?}.ord], :rvim_paragraph_forward)
      @config.add_default_key_binding_by_keymap(:vi_command, [?R.ord], :rvim_enter_replace_mode)
      @config.add_default_key_binding_by_keymap(:vi_command, [?r.ord], :rvim_replace_one)
      @config.add_default_key_binding_by_keymap(:vi_command, [?d.ord], :rvim_delete_op)
      @config.add_default_key_binding_by_keymap(:vi_command, [?c.ord], :rvim_change_op)
      @config.add_default_key_binding_by_keymap(:vi_command, [?y.ord], :rvim_yank_op)
      @config.add_default_key_binding_by_keymap(:vi_command, [0x1E], :rvim_alternate_file) # Ctrl-^
      @config.add_default_key_binding_by_keymap(:vi_command, [?s.ord], :rvim_substitute_char)
      @config.add_default_key_binding_by_keymap(:vi_command, [?S.ord], :rvim_substitute_line)
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
        lsp.did_open(buf) if path && @settings.get(:lsp_enabled)
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

      if expanded.end_with?('.lua')
        lua.load_file(expanded)
        return true
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

    def add_buffer(path)
      find_or_create_buffer(path)
    end

    def open_terminal_buffer(name, lines, status: 0)
      buf = Rvim::Buffer.new(@next_buffer_id, name, encoding: encoding)
      @next_buffer_id += 1
      buf.lines = lines.map { |l| l.dup.force_encoding(encoding) }
      buf.line_index = 0
      buf.byte_pointer = 0
      buf.modified = false
      @buffers[buf.id] = buf
      @buffer_order << buf.id
      swap_to_buffer(buf)
      @status_message = "[terminal] #{name} exited #{status}"
    end

    private def find_or_create_buffer(path)
      existing = @buffers.values.find { |b| b.filepath == path } if path
      return existing if existing

      buf = Rvim::Buffer.new(@next_buffer_id, path, encoding: encoding)
      @next_buffer_id += 1
      @buffers[buf.id] = buf
      @buffer_order << buf.id

      ft = Rvim::Syntax.detect_language(path)
      if ft
        Rvim::FileType.run(ft, buf, self)
        load_filetype_scripts(ft)
      end

      buf
    end

    class RedirFile
      def initialize(path, mode)
        @file = File.open(path, mode)
      end

      def <<(msg)
        @file.puts(msg)
        @file.flush
      end

      def close
        @file.close
      end
    end

    class RedirRegister
      def initialize(editor, name)
        @editor = editor
        @name = name
        @buf = +''
      end

      def <<(msg)
        @buf << msg.to_s << "\n"
      end

      def close
        @editor.write_register(@buf, :line, register: @name) if @editor.respond_to?(:write_register)
      end
    end

    def open_redir_file(path, mode)
      close_redir
      @redir_sink = RedirFile.new(path, mode)
    rescue => e
      @status_message = "E484: Can't open file #{path}: #{e.message}"
    end

    def open_redir_register(name)
      close_redir
      @redir_sink = RedirRegister.new(self, name)
    end

    def close_redir
      @redir_sink&.close
      @redir_sink = nil
    end

    attr_reader :undo_timestamps

    def push_undo_redo(modified)
      super
      @undo_timestamps ||= []
      if modified
        # Reline replaces history past @undo_redo_index then pushes one.
        # Mirror that for our timestamps array.
        @undo_timestamps = @undo_timestamps[0..(@undo_redo_index - 1)] || []
        @undo_timestamps.push(Time.now)
      else
        # Same-index update — refresh that timestamp.
        @undo_timestamps[@undo_redo_index] = Time.now
      end
    end

    def travel_undo_seconds(delta)
      stamps = @undo_timestamps || []
      return if stamps.empty?

      target_time = Time.now + delta
      # Find the nearest history entry whose timestamp is <= target_time when
      # going earlier, or >= target_time when going later. Default to clamping.
      target_index = if delta < 0
                       i = stamps.size - 1
                       i -= 1 while i > 0 && stamps[i] && stamps[i] > target_time
                       i
                     else
                       i = 0
                       i += 1 while i < stamps.size - 1 && stamps[i] && stamps[i] < target_time
                       i
                     end
      diff = target_index - @undo_redo_index
      if diff < 0
        diff.abs.times { send(:undo, nil) }
      elsif diff > 0
        diff.times { send(:redo, nil) }
      end
    end

    HELP_PATH = File.expand_path(File.join(__dir__, 'help', 'help.txt')).freeze

    def open_help_buffer(topic = nil)
      unless File.file?(HELP_PATH)
        @status_message = 'E149: No help available'
        return
      end

      open(HELP_PATH)
      jump_to_help_tag(topic) if topic
    end

    def close_help_buffer
      buf = @buffers.values.find { |b| b.filepath == HELP_PATH }
      return unless buf

      remove_buffer(buf) if respond_to?(:remove_buffer)
    end

    private def jump_to_help_tag(topic)
      tag_pattern = "*#{topic}*"
      lines = @buffer_of_lines || []
      idx = lines.find_index { |line| line.include?(tag_pattern) }
      if idx
        @line_index = idx
        @byte_pointer = (lines[idx] || '').index(tag_pattern) || 0
      else
        @status_message = "E149: Sorry, no help for #{topic}"
      end
    end

    def load_filetype_scripts(ft)
      return unless ft

      ft = ft.to_s
      rtp = @settings.get(:runtimepath).to_s.split(',').map { |p| File.expand_path(p.strip) }.reject(&:empty?)
      return if rtp.empty?

      %w[ftplugin indent syntax].each do |kind|
        rtp.each do |dir|
          path = File.join(dir, kind, "#{ft}.vim")
          source(path) if File.file?(path)
        end
      end
    end

    def swap_to_buffer(buf)
      @alternate_filepath = @filepath if @current_buffer && @filepath != buf.filepath
      save_current_buffer if @current_buffer
      if @settings.get(:autoread) && buf.file_changed_externally? && !buf.modified
        buf.reload(encoding: encoding)
      end
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

      autowrite_if_modified
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
      # splitright (vertical) / splitbelow (horizontal) put the new window AFTER
      # the current one. The opposite putt puts it BEFORE (default vim behavior).
      after = if @split_orientation == :vertical
                @settings.get(:splitright)
              else
                @settings.get(:splitbelow)
              end
      insert_at = after ? idx + 1 : idx
      @windows.insert(insert_at, win)
      @current_window = win
      equalize_windows if @settings.get(:equalalways)
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
      ead = @settings.get(:eadirection).to_s
      @windows.each do |w|
        case ead
        when 'hor'
          w.extra_rows = 0
        when 'ver'
          w.extra_cols = 0
        else
          w.extra_rows = 0
          w.extra_cols = 0
        end
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

    attr_reader :tag_stack, :tag_matches, :tag_match_index
    attr_accessor :last_bang_cmd, :alternate_filepath
    attr_reader :arg_list
    attr_accessor :arg_index

    private def rvim_tag_jump(key, arg: 1)
      word = word_at_cursor
      return unless word

      tag_jump(word)
    end

    private def rvim_tag_pop(key, arg: 1)
      tag_pop
    end

    def tag_jump(name)
      reload_tags_if_needed
      matches = Rvim::Tags.find(name)
      if matches.empty?
        @status_message = "E426: tag not found: #{name}"
        return
      end

      push_tag_stack(name)
      @tag_matches = matches
      @tag_match_index = 0
      jump_to_tag_entry(matches.first)
    end

    def tag_pop
      if @tag_stack.empty?
        @status_message = 'E555: at bottom of tag stack'
        return
      end

      entry = @tag_stack.pop
      open(entry[:file]) if entry[:file] && entry[:file] != @filepath
      @line_index = entry[:line_index].clamp(0, [@buffer_of_lines.size - 1, 0].max)
      target = @buffer_of_lines[@line_index] || ''
      @byte_pointer = entry[:byte_pointer].clamp(0, target.bytesize)
    end

    def tag_next
      return @status_message = 'E73: no more matches' if @tag_matches.empty?

      @tag_match_index = (@tag_match_index + 1).clamp(0, @tag_matches.size - 1)
      jump_to_tag_entry(@tag_matches[@tag_match_index])
    end

    def tag_prev
      return @status_message = 'E73: no more matches' if @tag_matches.empty?

      @tag_match_index = (@tag_match_index - 1).clamp(0, @tag_matches.size - 1)
      jump_to_tag_entry(@tag_matches[@tag_match_index])
    end

    private def push_tag_stack(name)
      @tag_stack << {
        name: name,
        file: @filepath,
        line_index: @line_index,
        byte_pointer: @byte_pointer,
      }
    end

    private def jump_to_tag_entry(entry)
      open(entry.file) if entry.file && entry.file != @filepath
      target = Rvim::Tags.locate(entry.excmd, @buffer_of_lines)
      if target
        push_jump
        @line_index = target[0].clamp(0, [@buffer_of_lines.size - 1, 0].max)
        line_text = @buffer_of_lines[@line_index] || ''
        @byte_pointer = target[1].clamp(0, line_text.bytesize)
      else
        @status_message = "E433: tag location not found: #{entry.excmd}"
      end
    end

    def set_arg_list(paths)
      @arg_list = Array(paths).map(&:to_s)
      @arg_index = 0
    end

    def add_arg(path)
      @arg_list << path.to_s
    end

    def reload_tags_if_needed
      paths = @settings.get(:tags).to_s.split(',').map(&:strip).reject(&:empty?)
      return if paths == Rvim::Tags.loaded_paths

      Rvim::Tags.load(paths)
    end

    private def rvim_completion_chain(key, arg: 1)
      @completion_chain_pending = true
    end

    private def configured_pum_height
      h = @settings.get(:pumheight).to_i
      h.positive? ? h : Rvim::CompletionPopup::DEFAULT_MAX_HEIGHT
    end

    private def start_completion_with_source(source, delta)
      line = @buffer_of_lines[@line_index] || ''
      case source
      when :filenames
        base = Rvim::Completion.path_base_at(line, @byte_pointer)
        base_byte = Rvim::Completion.path_base_start(line, @byte_pointer)
        candidates = Rvim::Completion.candidates_files(base)
      when :dictionary
        base = Rvim::Completion.base_at(line, @byte_pointer)
        base_byte = Rvim::Completion.base_start(line, @byte_pointer)
        candidates = Rvim::Completion.candidates_dictionary(base)
      when :lines
        base = line.byteslice(0, @byte_pointer) || ''
        base_byte = 0
        candidates = Rvim::Completion.candidates_lines(@buffer_of_lines, base)
      end

      if candidates.empty?
        @status_message = 'Pattern not found'
        return
      end

      @completion_active = true
      @completion_candidates = candidates
      @completion_index = delta < 0 ? candidates.size - 1 : 0
      @completion_base = base
      @completion_base_byte = base_byte
      @completion_line_index = @line_index
      @completion_popup = Rvim::CompletionPopup.new(contents: candidates, pointer: @completion_index, max_height: configured_pum_height)
      replace_completion_with(@completion_candidates[@completion_index])
      update_completion_status
    end

    private def rvim_insert_newline(key, arg: 1)
      cur_line = @buffer_of_lines[@line_index] || ''
      head = cur_line.byteslice(0, @byte_pointer) || +''
      tail = cur_line.byteslice(@byte_pointer, cur_line.bytesize - @byte_pointer) || +''

      paste = @settings.get(:paste)
      ai = @settings.get(:autoindent)
      si = @settings.get(:smartindent)
      indent = (!paste && (ai || si)) ? cur_line[/\A[ \t]*/].to_s.dup : ''

      if !paste && si
        sw = @settings.get(:shiftwidth).to_i
        sw = 2 if sw <= 0
        if head.rstrip.end_with?('{')
          indent << (' ' * sw)
        end
        if tail.lstrip.start_with?('}')
          remove = [sw, indent.length].min
          indent = indent[0...indent.length - remove].to_s
        end
      end

      @buffer_of_lines[@line_index] = String.new(head, encoding: encoding)
      new_line = String.new(indent + tail, encoding: encoding)
      @buffer_of_lines.insert(@line_index + 1, new_line)
      @line_index += 1
      @byte_pointer = indent.bytesize
      @modified = true
    end

    private def rvim_insert_tab(key, arg: 1)
      if @settings.get(:expandtab)
        n = @settings.get(:shiftwidth).to_i
        n = 2 if n <= 0
        insert_at_cursor(' ' * n)
      else
        insert_at_cursor("\t")
      end
    end

    private def rvim_digraph_start(key, arg: 1)
      @digraph_pending = true
      @digraph_chars = +''
    end

    private def capture_digraph_key(key)
      ch = key.char.to_s
      @digraph_chars << ch
      return if @digraph_chars.length < 2

      pair = @digraph_chars[0, 2]
      result = Rvim::Digraphs.lookup(pair)
      @digraph_pending = false
      @digraph_chars = +''
      if result
        insert_at_cursor(result)
      else
        @status_message = "E1050: unknown digraph: #{pair}"
      end
    end

    # Coerce a string to valid UTF-8 so downstream String#split / regex work
    # safely. Pasted content from the system clipboard, file contents loaded
    # with a different external encoding, or yanked binary blobs may all
    # arrive labeled as ASCII-8BIT or with invalid byte sequences.
    private def ensure_utf8(s)
      return s if s.encoding == Encoding::UTF_8 && s.valid_encoding?

      out = s.dup.force_encoding(Encoding::UTF_8)
      out.valid_encoding? ? out : out.scrub('?')
    end

    def insert_at_cursor(s)
      line = @buffer_of_lines[@line_index] || +''
      head = line.byteslice(0, @byte_pointer) || +''
      tail = line.byteslice(@byte_pointer, line.bytesize - @byte_pointer) || +''
      @buffer_of_lines[@line_index] = String.new(head + s + tail, encoding: encoding)
      @byte_pointer += s.bytesize
      @modified = true
    end

    private def rvim_enter_replace_mode(key)
      @replace_mode = true
      @replace_originals = []
      @config.editing_mode = :vi_insert
    end

    # `s` — substitute character: delete N chars under the cursor and enter
    # insert mode. Equivalent to `cl` with a count. The deleted text goes
    # into the unnamed register, matching vim.
    private def rvim_substitute_char(key, arg: 1)
      count = arg
      line = @buffer_of_lines[@line_index] || +''
      pos = @byte_pointer
      # Advance by `count` *characters* (mbchar-aware), not bytes — so `s` on
      # 'あ' deletes the whole 3-byte codepoint, not a single leading byte
      # that would leave invalid UTF-8 behind.
      take = 0
      remaining = count
      while remaining.positive? && (pos + take) < line.bytesize
        size = Reline::Unicode.get_next_mbchar_size(line, pos + take)
        size = 1 if size <= 0
        take += size
        remaining -= 1
      end
      if take.positive?
        deleted = line.byteslice(pos, take)
        write_register(deleted, :char) if deleted
        @buffer_of_lines[@line_index] = String.new(
          line.byteslice(0, pos).to_s + line.byteslice(pos + take, line.bytesize - pos - take).to_s,
          encoding: encoding,
        )
        sync_current_buffer_lines
        @modified = true
      end
      @config.editing_mode = :vi_insert
    end

    # `S` — substitute line: blank out the current line and enter insert at
    # column 0 (or at the autoindent column if set). Same as `cc`.
    private def rvim_substitute_line(key, arg: 1)
      yanked = []
      arg.times do |i|
        li = @line_index + i
        break if li >= @buffer_of_lines.size

        yanked << (@buffer_of_lines[li] || '').dup
        @buffer_of_lines[li] = String.new('', encoding: encoding)
      end
      write_register(yanked.join("\n"), :line) unless yanked.empty?
      @byte_pointer = 0
      sync_current_buffer_lines
      @modified = true
      @config.editing_mode = :vi_insert
    end

    private def rvim_alternate_file(key)
      alt = @alternate_filepath
      if alt.nil? || alt.empty?
        @status_message = 'E23: No alternate file'
        return
      end
      buf = @buffers.values.find { |b| b.filepath == alt }
      if buf
        swap_to_buffer(buf)
      else
        # Alternate file isn't in the buffer list — load it.
        open(alt)
      end
    end

    private def rvim_replace_one(key, arg: 1)
      count = arg
      @waiting_proc = lambda do |k, _sym|
        @waiting_proc = nil
        ch = k.is_a?(Integer) ? k.chr : k.to_s
        next if ch.nil? || ch.empty?
        next if ch == "\e" # Esc cancels

        replace_chars_at_cursor(ch, count)
      end
    end

    private def rvim_delete_op(key, arg: 1)
      enter_pending_op(:delete, arg)
    end

    private def rvim_change_op(key, arg: 1)
      enter_pending_op(:change, arg)
    end

    private def rvim_yank_op(key, arg: 1)
      enter_pending_op(:yank, arg)
    end

    private def enter_pending_op(op, count)
      @rvim_pending_op = op
      @rvim_pending_op_count = (count.is_a?(Integer) && count > 0) ? count : 1
    end

    def replace_chars_at_cursor(ch, count)
      line = @buffer_of_lines[@line_index] || +''
      pos = @byte_pointer
      count.times do
        break if pos >= line.bytesize

        size = Reline::Unicode.get_next_mbchar_size(line, pos)
        size = 1 if size <= 0
        line = String.new(line.byteslice(0, pos).to_s + ch + line.byteslice(pos + size, line.bytesize - pos - size).to_s, encoding: encoding)
        pos += ch.bytesize
      end
      @buffer_of_lines[@line_index] = line
      @byte_pointer = [pos - ch.bytesize, 0].max
      @modified = true
    end

    def replace_overwrite_at_cursor(s)
      line = @buffer_of_lines[@line_index] || +''
      pos = @byte_pointer
      if pos >= line.bytesize
        @replace_originals << :extend
        @buffer_of_lines[@line_index] = String.new(line + s, encoding: encoding)
      else
        size = Reline::Unicode.get_next_mbchar_size(line, pos)
        size = 1 if size <= 0
        original = line.byteslice(pos, size)
        @replace_originals << original
        @buffer_of_lines[@line_index] = String.new(line.byteslice(0, pos).to_s + s + line.byteslice(pos + size, line.bytesize - pos - size).to_s, encoding: encoding)
      end
      @byte_pointer += s.bytesize
      @modified = true
    end

    def replace_undo_at_cursor
      return false if @replace_originals.empty?

      original = @replace_originals.pop
      line = @buffer_of_lines[@line_index] || +''
      if original == :extend
        # Char was appended past the original EOL — drop the last byte.
        return false if @byte_pointer <= 0

        size = Reline::Unicode.get_prev_mbchar_size(line, @byte_pointer)
        @buffer_of_lines[@line_index] = String.new(line.byteslice(0, @byte_pointer - size).to_s + line.byteslice(@byte_pointer, line.bytesize - @byte_pointer).to_s, encoding: encoding)
        @byte_pointer -= size
      else
        # Step back over the inserted char and restore the original byte(s).
        return false if @byte_pointer <= 0

        size = Reline::Unicode.get_prev_mbchar_size(line, @byte_pointer)
        before = line.byteslice(0, @byte_pointer - size).to_s
        after = line.byteslice(@byte_pointer, line.bytesize - @byte_pointer).to_s
        @buffer_of_lines[@line_index] = String.new(before + original + after, encoding: encoding)
        @byte_pointer -= size
      end
      true
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
        @completion_popup&.pointer = @completion_index
        update_completion_status
      else
        start_completion(delta)
      end
    end

    private def start_completion(delta)
      line = @buffer_of_lines[@line_index] || ''
      base = Rvim::Completion.base_at(line, @byte_pointer)

      keyword = Rvim::Completion.candidates(@buffer_of_lines, base, infercase: @settings.get(:infercase))
      lsp_cands = collect_lsp_completion_candidates(base)

      # Order: LSP candidates first (when present), then keyword
      # candidates with anything already in the LSP list filtered out.
      # Always offer keyword candidates so the popup has something even
      # when ruby-lsp returns [] for bare-identifier contexts.
      candidates = lsp_cands + (keyword - lsp_cands)
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
      @completion_popup = Rvim::CompletionPopup.new(contents: candidates, pointer: @completion_index, max_height: configured_pum_height)
      replace_completion_with(@completion_candidates[@completion_index]) unless completeopt_flags.include?('noinsert')
      update_completion_status
    end

    LSP_COMPLETION_TIMEOUT = 1.5

    # Send textDocument/completion at the cursor, wait briefly, return
    # the candidate text strings (insertText preferred, else label),
    # filtered to those starting with `base`. Empty array when LSP is
    # off / no client / no items / timed out.
    private def collect_lsp_completion_candidates(base)
      return [] unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return [] unless buf
      lsp.flush_changes(buf)
      return [] unless lsp.request_completion(buf)

      deadline = Time.now + LSP_COMPLETION_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_completion_result
        break if result
        break unless lsp.pending_for?('textDocument/completion')
        break if Time.now > deadline

        sleep 0.02
      end

      items = extract_completion_items(result)
      texts = items.map { |it| completion_item_text(it) }.compact.uniq
      texts = texts.select { |t| t.start_with?(base) } unless base.empty?
      texts
    end

    # Normalize the raw textDocument/completion result into a flat
    # Array of CompletionItem hashes. Handles CompletionItem[],
    # CompletionList ({ isIncomplete, items }), and null.
    private def extract_completion_items(result)
      case result
      when nil then []
      when Array then result
      when Hash then Array(result[:items])
      else []
      end
    end

    # Text used to display + insert for a CompletionItem. Prefer
    # `insertText` when present, otherwise `label`.
    private def completion_item_text(item)
      txt = item[:insertText] || item[:label]
      txt&.to_s
    end

    private def completeopt_flags
      @settings.get(:completeopt).to_s.split(',').map(&:strip)
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
      @completion_popup = nil
    end

    attr_reader :completion_popup, :completion_base_byte, :completion_line_index
    attr_reader :hover_popup, :signature_popup

    private def completion_key?(key)
      sym = key.method_symbol
      sym == :rvim_complete_next || sym == :rvim_complete_prev
    end

    attr_reader :completion_active, :completion_candidates, :completion_index

    private def rvim_bracket_left(key, arg: 1)
      @waiting_proc = lambda do |k, _sym|
        @waiting_proc = nil
        ch = k.is_a?(Integer) ? k.chr : k.to_s
        case ch
        when 'c' then diff_jump(:prev)
        when 's' then jump_to_misspelling(:prev)
        when 'd' then jump_to_diagnostic(:prev)
        end
      end
    end

    private def rvim_bracket_right(key, arg: 1)
      @waiting_proc = lambda do |k, _sym|
        @waiting_proc = nil
        ch = k.is_a?(Integer) ? k.chr : k.to_s
        case ch
        when 'c' then diff_jump(:next)
        when 's' then jump_to_misspelling(:next)
        when 'd' then jump_to_diagnostic(:next)
        end
      end
    end

    # Jump to the next or previous LSP diagnostic relative to the cursor.
    # Diagnostics are walked in (line, character) order. No-wrap: when
    # there's nothing further in `direction`, surface a status message
    # and leave the cursor where it is. Push the current position onto
    # the jump list so Ctrl-O comes back.
    def jump_to_diagnostic(direction)
      buf = current_buffer
      return unless buf

      diags = lsp.diagnostics_for(buf)
      if diags.empty?
        @status_message = 'LSP: no diagnostics'
        return
      end

      positions = diags.map do |d|
        [d.dig(:range, :start, :line).to_i, d.dig(:range, :start, :character).to_i]
      end.sort

      cur = [@line_index, @byte_pointer]
      target = if direction == :next
                 positions.find { |p| (p <=> cur) > 0 }
               else
                 positions.reverse_each.find { |p| (p <=> cur) < 0 }
               end

      if target.nil?
        @status_message = direction == :next ? 'LSP: no next diagnostic' : 'LSP: no previous diagnostic'
        return
      end

      push_jump
      @line_index = target[0]
      @byte_pointer = target[1]
    end

    def jump_to_misspelling(direction)
      return unless @settings.get(:spell)

      bp = @byte_pointer
      li = @line_index
      lines = @buffer_of_lines
      total = lines.size

      forward = direction == :next
      step = forward ? +1 : -1
      cur_li = li
      cur_bp = bp

      visited = 0
      while visited < total
        line = lines[cur_li] || ''
        positions = scan_word_positions(line)
        positions.sort_by! { |s, _| s }
        positions.reverse! unless forward
        positions.each do |start_byte, end_byte|
          if cur_li == li
            next if forward && start_byte <= bp
            next if !forward && start_byte >= bp
          end

          word = line.byteslice(start_byte, end_byte - start_byte)
          if Rvim::Spell.misspelled?(word)
            push_jump
            @line_index = cur_li
            @byte_pointer = start_byte
            return
          end
        end

        cur_li += step
        break if cur_li.negative? || cur_li >= total

        visited += 1
      end
    end

    private def scan_word_positions(line)
      positions = []
      line.to_s.scan(/[A-Za-z]+/) do |w|
        m = Regexp.last_match
        positions << [m.begin(0), m.end(0)]
      end
      positions
    end

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
      # Prefer LSP textDocument/definition when an LSP client is available
      # for this filetype. Falls through to vim's classic in-buffer search
      # when LSP is off / no server / no result.
      return if lsp_jump_to_definition

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

    # Send textDocument/definition for the cursor's symbol, poll for the
    # response, and jump to the target. Returns true when the LSP path
    # took over (whether it found a target or surfaced "no definition"
    # status), false to let the caller try a fallback.
    LSP_DEFINITION_TIMEOUT = 2.0

    def lsp_jump_to_definition
      return false unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return false unless buf
      lsp.flush_changes(buf)
      return false unless lsp.request_definition(buf)

      deadline = Time.now + LSP_DEFINITION_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_definition_result
        break if result
        break unless lsp.pending_for?('textDocument/definition')
        break if Time.now > deadline

        sleep 0.02
      end

      location = first_lsp_location(result)
      if location.nil?
        @status_message = 'LSP: no definition found'
        return true
      end

      target_uri = location[:uri] || location[:targetUri]
      target_range = location[:range] || location[:targetRange] || location[:targetSelectionRange]
      return true if target_uri.nil? || target_range.nil?

      target_path = target_uri.sub(/\Afile:\/\//, '')
      target_line = target_range.dig(:start, :line).to_i
      target_char = target_range.dig(:start, :character).to_i

      push_jump
      open(target_path) if target_path != @filepath
      @line_index = target_line
      @byte_pointer = target_char
      true
    end

    private def first_lsp_location(result)
      case result
      when nil then nil
      when Array then result.first
      when Hash then result
      end
    end

    LSP_HOVER_TIMEOUT = 2.0
    HOVER_POPUP_MAX_WIDTH = 80
    HOVER_POPUP_MAX_HEIGHT = 16

    # Send textDocument/hover for the cursor's symbol, poll for the
    # response, and build @hover_popup. Returns true when the LSP path
    # took action (popup shown OR "no info" status), false to let the
    # caller fall back to keywordprg.
    def lsp_show_hover
      return false unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return false unless buf
      lsp.flush_changes(buf)
      return false unless lsp.request_hover(buf)

      deadline = Time.now + LSP_HOVER_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_hover_result
        break if result
        break unless lsp.pending_for?('textDocument/hover')
        break if Time.now > deadline

        sleep 0.02
      end

      lines = parse_hover_contents(result)
      if lines.empty?
        @status_message = 'LSP: no hover info'
        return true
      end

      @hover_popup = Rvim::CompletionPopup.new(
        contents: lines,
        max_width: HOVER_POPUP_MAX_WIDTH,
        max_height: HOVER_POPUP_MAX_HEIGHT,
      )
      true
    end

    # Normalize LSP hover responses to an Array<String>. Handles:
    # - { contents: { kind:, value: } }     (MarkupContent)
    # - { contents: { language:, value: } } (legacy MarkedString object)
    # - { contents: "..." }                 (legacy MarkedString string)
    # - { contents: [...] }                 (MarkedString[])
    # - nil / empty                          → []
    private def parse_hover_contents(result)
      return [] unless result

      contents = result.is_a?(Hash) ? result[:contents] : nil
      return [] unless contents

      case contents
      when String
        contents.split("\n", -1)
      when Hash
        (contents[:value] || '').split("\n", -1)
      when Array
        contents.flat_map do |c|
          case c
          when String then c.split("\n", -1)
          when Hash then (c[:value] || '').split("\n", -1)
          else []
          end
        end
      else
        []
      end
    end

    def dismiss_hover_popup
      @hover_popup = nil
    end

    LSP_SIGNATURE_HELP_TIMEOUT = 1.5
    SIGNATURE_POPUP_MAX_WIDTH  = 80
    SIGNATURE_POPUP_MAX_HEIGHT = 8

    # Send textDocument/signatureHelp, poll, parse the SignatureHelp
    # response, build @signature_popup. Returns true when the LSP path
    # took action (popup shown OR "no info" status), false when LSP is
    # off / unavailable. `position_offset` lets the auto-trigger path
    # pull the request position one column back so it lands ON the
    # `(` / `,` rather than past it (ruby-lsp's CallNode end_offset is
    # exclusive).
    def lsp_show_signature_help(position_offset: 0)
      return false unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return false unless buf

      # ruby-lsp 0.26.x has a race: its reader thread pre-parses on
      # requests, but its worker thread applies didChange edits. A
      # signatureHelp sent right after a didChange can run against the
      # OLD parse_result (or worse, parse against stale @source). When
      # we just sent a didChange via flush_changes, settle briefly so
      # the worker has time to apply the edit before our request lands.
      flushed = lsp.flush_changes(buf)
      sleep SIGNATURE_HELP_DIDCHANGE_SETTLE if flushed

      char = [@byte_pointer + position_offset, 0].max
      return false unless lsp.request_signature_help(buf, line: @line_index, character: char)

      deadline = Time.now + LSP_SIGNATURE_HELP_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_signature_help_result
        break if result
        break unless lsp.pending_for?('textDocument/signatureHelp')
        break if Time.now > deadline

        sleep 0.02
      end

      lines = parse_signature_help(result)
      if lines.empty?
        @signature_popup = nil
        @status_message = 'LSP: no signature info'
        return true
      end

      @signature_popup = Rvim::CompletionPopup.new(
        contents: lines,
        max_width: SIGNATURE_POPUP_MAX_WIDTH,
        max_height: SIGNATURE_POPUP_MAX_HEIGHT,
      )
      true
    end

    SIGNATURE_HELP_DIDCHANGE_SETTLE = 0.05

    # Normalize a SignatureHelp response into Array<String> for the popup.
    # The active signature gets a `> ` prefix; the active parameter is
    # wrapped in « » markers. Documentation strings are intentionally
    # omitted — ruby-lsp returns huge rdoc markdown that would flood
    # the popup; users can press K for the full hover anyway.
    private def parse_signature_help(result)
      return [] unless result.is_a?(Hash)

      sigs = result[:signatures]
      return [] unless sigs.is_a?(Array) && !sigs.empty?

      active_sig_idx = (result[:activeSignature] || 0).to_i.clamp(0, sigs.size - 1)
      sigs.each_with_index.map do |sig, idx|
        prefix = idx == active_sig_idx ? '> ' : '  '
        active_param_idx = (sig[:activeParameter] || result[:activeParameter] || 0).to_i
        "#{prefix}#{format_signature_label(sig, active_param_idx)}"
      end
    end

    # Highlight the active parameter inside the signature label using
    # « » markers. ParameterInformation.label can be a String or a
    # [start, end] byte offset pair into the signature label.
    private def format_signature_label(sig, active_param_idx)
      label = sig[:label].to_s
      params = sig[:parameters]
      return label unless params.is_a?(Array)
      return label unless active_param_idx >= 0 && active_param_idx < params.size

      param_label = params[active_param_idx][:label]
      case param_label
      when Array
        s, e = param_label.map(&:to_i)
        return label if s.nil? || e.nil? || s > e || e > label.length

        "#{label[0...s]}«#{label[s...e]}»#{label[e..]}"
      when String
        idx = label.index(param_label)
        return label unless idx

        head = label[0...idx]
        tail = label[(idx + param_label.length)..]
        "#{head}«#{param_label}»#{tail}"
      else label
      end
    end

    def dismiss_signature_popup
      @signature_popup = nil
    end

    LSP_REFERENCES_TIMEOUT = 2.0

    # Send textDocument/references for the cursor's symbol, poll for the
    # response, populate the quickfix list with one entry per Location,
    # and jump to the first. Returns true when the LSP path took action,
    # false to allow caller fallback.
    def lsp_find_references
      return false unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return false unless buf
      lsp.flush_changes(buf)
      return false unless lsp.request_references(buf)

      deadline = Time.now + LSP_REFERENCES_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_references_result
        break if result
        break unless lsp.pending_for?('textDocument/references')
        break if Time.now > deadline

        sleep 0.02
      end

      locations = result || []
      if locations.empty?
        @status_message = 'LSP: no references'
        return true
      end

      entries = build_references_entries(locations)
      if entries.empty?
        @status_message = 'LSP: no references'
        return true
      end

      @quickfix.set(entries)
      jump_to_quickfix_entry(entries.first)
      first = entries.first
      @status_message = "(1 of #{entries.size}) #{first.file}:#{first.line}:#{first.col}"
      true
    end

    private def build_references_entries(locations)
      file_lines_cache = {}
      locations.filter_map do |loc|
        uri = loc[:uri] || loc[:targetUri]
        range = loc[:range] || loc[:targetRange] || loc[:targetSelectionRange]
        next nil if uri.nil? || range.nil?

        path = uri.sub(/\Afile:\/\//, '')
        line_idx = range.dig(:start, :line).to_i
        col_idx = range.dig(:start, :character).to_i
        file_lines_cache[path] ||= safe_read_lines(path)
        text = (file_lines_cache[path][line_idx] || '').strip
        Rvim::Quickfix::Entry.new(file: path, line: line_idx + 1, col: col_idx + 1, text: text)
      end
    end

    private def safe_read_lines(path)
      File.readlines(path, chomp: true)
    rescue StandardError
      []
    end

    LSP_FORMAT_TIMEOUT = 5.0
    LSP_SYMBOLS_TIMEOUT = 2.0
    LSP_WORKSPACE_SYMBOLS_TIMEOUT = 5.0
    LSP_RENAME_TIMEOUT = 5.0
    LSP_CODE_ACTION_TIMEOUT = 3.0

    # Request available code actions at the cursor, cache them on the
    # editor, and show the list in the listing overlay numbered so the
    # user can apply one via `:LspCodeAction N`. Returns true when the
    # LSP path took action (list shown or "none available" surfaced).
    def lsp_show_code_actions
      return false unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return false unless buf
      lsp.flush_changes(buf)
      return false unless lsp.request_code_actions(buf)

      deadline = Time.now + LSP_CODE_ACTION_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_code_actions_result
        break if result
        break unless lsp.pending_for?('textDocument/codeAction')
        break if Time.now > deadline

        sleep 0.02
      end

      actions = Array(result)
      if actions.empty?
        @last_code_actions = nil
        @status_message = 'LSP: no code actions available'
        return true
      end

      @last_code_actions = actions
      rows = ['Code actions:']
      actions.each_with_index do |a, i|
        title = a[:title].to_s
        kind = a[:kind].to_s
        suffix = kind.empty? ? '' : " [#{kind}]"
        rows << format('  %d. %s%s', i + 1, title, suffix)
      end
      rows << '(:LspCodeAction <N> to apply)'
      show_list(rows)
      true
    end

    # Apply the Nth (1-based) cached code action. CodeAction may carry an
    # `edit` (WorkspaceEdit) and/or a `command` (executed server-side via
    # workspace/executeCommand). When the server returned the action
    # unresolved (only `data`, no `edit`/`command`), this calls
    # codeAction/resolve first to fill it in. Both edit and command are
    # honored when present, in spec order: edits first, then command.
    def lsp_apply_code_action(index_1_based)
      return false unless @last_code_actions
      idx = index_1_based.to_i - 1
      return false unless idx.between?(0, @last_code_actions.size - 1)

      action = @last_code_actions[idx]
      buf = current_buffer

      # If the server can resolve (deferred edit/command) and this action
      # is incomplete, fetch the resolved form before applying.
      if buf && action[:edit].nil? && action[:command].nil? &&
         lsp.respond_to?(:code_action_resolve_required?) &&
         lsp.code_action_resolve_required?(buf)
        if lsp.request_code_action_resolve(buf, action)
          deadline = Time.now + LSP_CODE_ACTION_TIMEOUT
          loop do
            lsp.pump
            resolved = lsp.last_code_action_resolve_result
            break action = resolved if resolved
            break unless lsp.pending_for?('codeAction/resolve')
            break if Time.now > deadline

            sleep 0.02
          end
        end
      end

      applied = false

      if action[:edit]
        pre_buffer = @buffer_of_lines.map(&:dup)
        apply_workspace_edit(action[:edit])
        push_undo_redo(true) if pre_buffer != @buffer_of_lines
        @modified = true if pre_buffer != @buffer_of_lines
        sync_current_buffer_lines
        applied = true
      end

      if action[:command]
        cmd = action[:command]
        # CodeAction's command field can be a Command object or a string
        # (rare; older spec). Normalize.
        cmd_obj = cmd.is_a?(Hash) ? cmd : { command: cmd.to_s }
        if buf && cmd_obj[:command]
          lsp.request_execute_command(buf, cmd_obj[:command].to_s, cmd_obj[:arguments])
          applied = true
        end
      end

      @status_message = applied ? "LSP: applied '#{action[:title]}'" : 'LSP: action had nothing to apply'
      true
    end

    # Send textDocument/rename for the cursor's symbol, poll for the
    # response, then apply the returned WorkspaceEdit across files.
    # Returns true when the LSP path took action, false to allow caller
    # fallback (e.g. the ex-command's status message).
    #
    # When the server advertises `renameProvider.prepareProvider: true`
    # (ruby-lsp does), `textDocument/prepareRename` is called first to
    # validate the position — if the server can't rename the symbol at
    # this point we surface a clearer message instead of "no edits".
    def lsp_rename_symbol(new_name)
      new_name = new_name.to_s
      return false if new_name.strip.empty?
      return false unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return false unless buf

      # Flush any unsynced edits so the server's view matches our cursor
      # position. Without this, a fast burst of edits followed by :LspRename
      # can leave the server's document a few chars behind, and prepareRename
      # at our cursor lands on the wrong node.
      lsp.flush_changes(buf)

      if lsp.rename_prepare_required?(buf)
        return false unless lsp.request_prepare_rename(buf)

        deadline = Time.now + LSP_RENAME_TIMEOUT
        prep = nil
        timed_out = false
        loop do
          lsp.pump
          prep = lsp.last_prepare_rename_result
          break if prep
          break unless lsp.pending_for?('textDocument/prepareRename')
          if Time.now > deadline
            timed_out = true
            break
          end

          sleep 0.02
        end

        if prep.nil?
          pos = "#{@line_index + 1}:#{@byte_pointer + 1}"
          @status_message = if timed_out
                              "LSP: prepareRename timed out at #{pos}"
                            else
                              "LSP: cannot rename at #{pos} (ruby-lsp 0.26 supports class/module names and constant references — not the `FOO = ...` definition site, methods, or local vars)"
                            end
          return true
        end
      end

      return false unless lsp.request_rename(buf, new_name)

      deadline = Time.now + LSP_RENAME_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_rename_result
        break if result
        break unless lsp.pending_for?('textDocument/rename')
        break if Time.now > deadline

        sleep 0.02
      end

      if result.nil?
        @status_message = 'LSP: rename returned no edits'
        return true
      end

      pre_buffer = @buffer_of_lines.map(&:dup)
      files_touched = apply_workspace_edit(result)

      if files_touched.zero?
        @status_message = 'LSP: rename produced no edits'
      else
        # If the current buffer changed, push an undo so `u` reverts it.
        push_undo_redo(true) if pre_buffer != @buffer_of_lines
        @status_message = "LSP: renamed to '#{new_name}' across #{files_touched} file#{files_touched == 1 ? '' : 's'}"
      end
      sync_current_buffer_lines
      true
    end

    # LSP SymbolKind enum (1-indexed). Maps to short labels we display in
    # the outline. Unknown kinds fall through to "symbol".
    SYMBOL_KIND_NAMES = {
      1 => 'file', 2 => 'module', 3 => 'namespace', 4 => 'package',
      5 => 'class', 6 => 'method', 7 => 'property', 8 => 'field',
      9 => 'constructor', 10 => 'enum', 11 => 'interface', 12 => 'function',
      13 => 'variable', 14 => 'constant', 15 => 'string', 16 => 'number',
      17 => 'boolean', 18 => 'array', 19 => 'object', 20 => 'key',
      21 => 'null', 22 => 'enum_member', 23 => 'struct', 24 => 'event',
      25 => 'operator', 26 => 'type_parameter'
    }.freeze

    # Send textDocument/documentSymbol, populate @quickfix with one entry
    # per symbol (indented by hierarchy), and show the outline via
    # show_list. Cursor is NOT moved — users navigate via :cnext/:cc/:cprev
    # or read the popover.
    def lsp_show_document_symbols
      return false unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return false unless buf
      return false unless lsp.request_document_symbols(buf)

      deadline = Time.now + LSP_SYMBOLS_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_document_symbols_result
        break if result
        break unless lsp.pending_for?('textDocument/documentSymbol')
        break if Time.now > deadline

        sleep 0.02
      end

      symbols = result || []
      if symbols.empty?
        @status_message = 'LSP: no symbols'
        return true
      end

      entries = flatten_symbols(symbols, @filepath || '')
      if entries.empty?
        @status_message = 'LSP: no symbols'
        return true
      end

      @quickfix.set(entries)
      show_list(Rvim::Command.format_quickfix(self))
      true
    end

    # Send workspace/symbol with `query`, populate @quickfix with one
    # entry per matching symbol from anywhere in the project. The
    # response is SymbolInformation[] | WorkspaceSymbol[] — both
    # carry a full `location` so flatten_symbols handles them.
    def lsp_show_workspace_symbols(query)
      return false unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return false unless buf
      return false unless lsp.request_workspace_symbols(buf, query)

      deadline = Time.now + LSP_WORKSPACE_SYMBOLS_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_workspace_symbols_result
        break if result
        break unless lsp.pending_for?('workspace/symbol')
        break if Time.now > deadline

        sleep 0.02
      end

      symbols = result || []
      if symbols.empty?
        @status_message = "LSP: no symbols match #{query.inspect}"
        return true
      end

      entries = flatten_symbols(symbols, @filepath || '')
      if entries.empty?
        @status_message = "LSP: no symbols match #{query.inspect}"
        return true
      end

      @quickfix.set(entries)
      show_list(Rvim::Command.format_quickfix(self))
      true
    end

    # Recursively walk the response, handling both DocumentSymbol (with
    # `range` / `selectionRange` / `children`) and SymbolInformation
    # (with `location.range` / `containerName`). Returns Quickfix::Entry[].
    private def flatten_symbols(items, file_path, depth: 0)
      items.flat_map do |item|
        if item[:location]
          # SymbolInformation — flat list, no children
          pos = item.dig(:location, :range, :start) || {}
          uri = item.dig(:location, :uri) || ''
          path = uri.sub(/\Afile:\/\//, '')
          path = file_path if path.empty?
          [build_symbol_entry(item, path, pos, depth)]
        else
          # DocumentSymbol — hierarchical
          pos = item.dig(:selectionRange, :start) || item.dig(:range, :start) || {}
          entry = build_symbol_entry(item, file_path, pos, depth)
          children = item[:children] || []
          [entry] + flatten_symbols(children, file_path, depth: depth + 1)
        end
      end
    end

    private def build_symbol_entry(item, file_path, pos, depth)
      kind = SYMBOL_KIND_NAMES[item[:kind]] || 'symbol'
      label = "#{'  ' * depth}#{kind} #{item[:name]}"
      Rvim::Quickfix::Entry.new(
        file: file_path,
        line: pos[:line].to_i + 1,
        col: pos[:character].to_i + 1,
        text: label,
      )
    end


    # Send textDocument/formatting and apply the returned TextEdit[] to
    # the current buffer. Returns true when the LSP path took action,
    # false to allow caller fallback.
    def lsp_format_buffer
      return false unless @settings.get(:lsp_enabled)

      buf = current_buffer
      return false unless buf
      return false unless lsp.request_formatting(buf)

      deadline = Time.now + LSP_FORMAT_TIMEOUT
      result = nil
      loop do
        lsp.pump
        result = lsp.last_formatting_result
        break if result
        break unless lsp.pending_for?('textDocument/formatting')
        break if Time.now > deadline

        sleep 0.02
      end

      edits = result || []
      if edits.empty?
        @status_message = 'LSP: no formatting changes'
        return true
      end

      pre_buffer = @buffer_of_lines.map(&:dup)
      apply_text_edits(edits)
      if pre_buffer == @buffer_of_lines
        @status_message = 'LSP: no formatting changes'
      else
        push_undo_redo(true)
        @modified = true
        @status_message = "LSP: formatted (#{edits.size} edit#{edits.size == 1 ? '' : 's'})"
      end
      sync_current_buffer_lines
      true
    end

    # Apply LSP TextEdit[] to @buffer_of_lines. Per spec, edits must be
    # applied in reverse-sorted order so earlier edits don't shift the
    # offsets of later ones.
    def apply_text_edits(edits)
      sort_text_edits_descending(edits).each { |e| apply_text_edit(e) }
    end

    private def apply_text_edit(edit)
      apply_text_edit_to_lines(@buffer_of_lines, edit)
      # Clamp cursor so it stays within the new buffer
      @line_index = @line_index.clamp(0, [@buffer_of_lines.size - 1, 0].max)
      cur_line = @buffer_of_lines[@line_index] || ''
      @byte_pointer = (@byte_pointer || 0).clamp(0, cur_line.bytesize)
    end

    # Splice a single LSP TextEdit into `lines` in place. Works on any
    # Array<String>, so callers can target the current @buffer_of_lines,
    # another buffer's lines array, or a transient array loaded from
    # disk for a not-currently-open file.
    private def apply_text_edit_to_lines(lines, edit)
      range = edit[:range]
      return unless range

      start_l = range.dig(:start, :line).to_i
      start_c = range.dig(:start, :character).to_i
      end_l = range.dig(:end, :line).to_i
      end_c = range.dig(:end, :character).to_i
      new_text = (edit[:newText] || '').to_s

      # Allow ranges that point one-past-end (`end_l == lines.size`,
      # `end_c == 0`) — ruby-lsp uses this to mean "end of document".
      start_l = start_l.clamp(0, [lines.size, 0].max)
      end_l = end_l.clamp(0, [lines.size, 0].max)

      start_line = lines[start_l] || ''
      end_line = lines[end_l] || ''
      start_c = start_c.clamp(0, start_line.bytesize)
      end_c = end_c.clamp(0, end_line.bytesize)

      prefix = start_line.byteslice(0, start_c) || ''
      suffix = end_line.byteslice(end_c, end_line.bytesize - end_c) || ''
      replacement = (prefix + new_text + suffix).split("\n", -1)
      lines[start_l..end_l] = replacement
    end

    # Apply an LSP WorkspaceEdit across (potentially many) files.
    # Per spec, prefer `documentChanges` if present (versioned form);
    # otherwise fall back to the legacy `changes` map. Returns the
    # number of files touched.
    #
    # For each target URI:
    #   - the CURRENT buffer is edited in-memory (via apply_text_edits)
    #     so undo (`u`) reverts the rename.
    #   - other already-open buffers are mutated in-place and marked
    #     modified; user commits with :w.
    #   - files not currently open are read from disk, edited, and
    #     written back (immediate). Saves the user from having to open
    #     every touched file.
    def apply_workspace_edit(workspace_edit)
      return 0 unless workspace_edit

      per_uri = {}
      if workspace_edit[:documentChanges].is_a?(Array)
        workspace_edit[:documentChanges].each do |dc|
          # Skip file create/rename/delete ops for v1 (kind != "text").
          next unless dc.is_a?(Hash) && dc[:textDocument] && dc[:edits].is_a?(Array)

          uri = dc.dig(:textDocument, :uri).to_s
          per_uri[uri] = (per_uri[uri] || []) + dc[:edits]
        end
      elsif workspace_edit[:changes].is_a?(Hash)
        workspace_edit[:changes].each do |uri, edits|
          uri_s = uri.to_s
          per_uri[uri_s] = (per_uri[uri_s] || []) + Array(edits)
        end
      end

      # Collapse multiple URIs pointing at the same physical file (macOS
      # ruby-lsp returns BOTH `file:///tmp/x.rb` and `file:///private/tmp/x.rb`
      # because /tmp is a symlink). Keep one representative URI per
      # canonical path; merge edit lists. Without this, we'd apply the
      # rename twice.
      by_canonical = {}
      per_uri.each do |uri, edits|
        cpath = canonical_path(uri.sub(/\Afile:\/\//, ''))
        entry = (by_canonical[cpath] ||= { uri: uri, edits: [] })
        entry[:edits].concat(edits)
      end

      by_canonical.count do |cpath, entry|
        apply_workspace_edit_for_uri(entry[:uri], cpath, entry[:edits])
      end
    end

    private def apply_workspace_edit_for_uri(uri, canonical, edits)
      return false if edits.nil? || edits.empty?

      buf = @buffers.values.find do |b|
        b.filepath && canonical_path(b.filepath) == canonical
      end

      if buf && buf == @current_buffer
        apply_text_edits(edits)
        @modified = true
        return true
      end

      if buf
        target_lines = buf.lines
        sort_text_edits_descending(edits).each { |e| apply_text_edit_to_lines(target_lines, e) }
        buf.modified = true
        return true
      end

      return false unless canonical && File.exist?(canonical)

      lines = File.readlines(canonical, chomp: true)
      sort_text_edits_descending(edits).each { |e| apply_text_edit_to_lines(lines, e) }
      trailing_newline = File.read(canonical).end_with?("\n")
      File.write(canonical, lines.join("\n") + (trailing_newline ? "\n" : ''))
      true
    end

    # Resolve symlinks (e.g. macOS /tmp → /private/tmp) and make the
    # path absolute, so two paths pointing at the same physical file
    # compare equal. Falls back to `expand_path` if the file is missing.
    private def canonical_path(path)
      return nil if path.nil? || path.empty?

      File.realpath(path)
    rescue StandardError
      File.expand_path(path)
    end

    private def sort_text_edits_descending(edits)
      edits.sort_by do |e|
        pos = e.dig(:range, :start) || {}
        [-(pos[:line] || 0), -(pos[:character] || 0)]
      end
    end

    # Jump to a Quickfix::Entry: open the target file (if different),
    # push the current position onto the jump list, then place the
    # cursor at the entry's 1-based line/col. Public so callers other
    # than the :cnext / :cprev / :grep family can reuse it (e.g.
    # lsp_find_references).
    def jump_to_quickfix_entry(entry)
      return unless entry

      open(entry.file) if entry.file && entry.file != @filepath
      push_jump
      @line_index = [entry.line - 1, 0].max
      target_line = @buffer_of_lines[@line_index] || ''
      @byte_pointer = (entry.col - 1).clamp(0, target_line.bytesize)
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
        when '=' then spell_show_suggestions
        when 'g' then spell_add_word_at_cursor(:good)
        when 'w' then spell_add_word_at_cursor(:bad)
        end
      end
    end

    def spell_show_suggestions
      word = word_at_cursor
      return unless word
      return unless Rvim::Spell.misspelled?(word)

      suggestions = Rvim::Spell.suggest(word)
      if suggestions.empty?
        @status_message = "Sorry, no suggestions"
        return
      end

      lines = ["Suggestions for '#{word}':"] + suggestions.each_with_index.map { |s, i| "  #{i + 1}. #{s}" }
      show_list(lines)
    end

    def spell_add_word_at_cursor(kind)
      word = word_at_cursor
      return unless word

      if kind == :good
        Rvim::Spell.add_good(word)
        @status_message = "Added '#{word}' to good spell list"
      else
        Rvim::Spell.add_bad(word)
        @status_message = "Added '#{word}' to bad spell list"
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

    def diff_buffers
      @buffers.values.select { |b| b.diff_active }
    end

    def recompute_diff_status
      bufs = diff_buffers
      bufs.each { |b| b.diff_status = nil }
      return if bufs.size < 2

      a, b = bufs[0], bufs[1]
      a_status, b_status = Rvim::Diff.compute(a.lines, b.lines)
      a.diff_status = a_status
      b.diff_status = b_status
    end

    def diff_jump(direction)
      buf = @current_buffer
      return unless buf && buf.diff_status

      starts = Rvim::Diff.hunk_starts(buf.diff_status)
      return if starts.empty?

      target = if direction == :next
                 starts.find { |s| s > @line_index }
               else
                 starts.reverse.find { |s| s < @line_index }
               end
      return unless target

      push_jump
      @line_index = target
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
      when 'indent'
        @folds.clear
        sw = @settings.get(:shiftwidth).to_i
        sw = 2 if sw <= 0
        Rvim::Folds.from_indent(@buffer_of_lines, sw).each do |s, e|
          @folds.add(s, e, closed: true)
        end
      end
      apply_fold_level
    end

    def apply_fold_level
      level = @settings.get(:foldlevel).to_i
      @folds.each do |f|
        f.closed = (f.level || 1) > level
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

      formats = nrformats_list

      # Try hex first (0x...) since '0' would otherwise look decimal.
      if formats.include?('hex')
        if (m = scan_hex_at(line, @byte_pointer))
          replace_number(line, m[:start], m[:end], (m[:value] + delta), :hex)
          return
        end
      end

      if formats.include?('bin')
        if (m = scan_bin_at(line, @byte_pointer))
          replace_number(line, m[:start], m[:end], (m[:value] + delta), :bin)
          return
        end
      end

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

    private def nrformats_list
      @settings.get(:nrformats).to_s.split(',').map(&:strip)
    end

    # Find a hex literal "0x[0-9a-fA-F]+" containing or after byte_pointer.
    private def scan_hex_at(line, byte_pointer)
      re = /0x[0-9a-fA-F]+/
      pos = [byte_pointer, 0].max
      while (m = re.match(line, pos))
        return nil if m.begin(0) > byte_pointer && byte_pointer > 0 && pos == byte_pointer && line.byteslice(byte_pointer, 1) =~ /\s/

        if m.begin(0) <= byte_pointer && m.end(0) > byte_pointer
          return { start: m.begin(0), end: m.end(0), value: m[0].to_i(16) }
        elsif m.begin(0) > byte_pointer
          return { start: m.begin(0), end: m.end(0), value: m[0].to_i(16) }
        end
        pos = m.end(0)
      end
      nil
    end

    private def scan_bin_at(line, byte_pointer)
      re = /0b[01]+/
      pos = [byte_pointer, 0].max
      while (m = re.match(line, pos))
        if m.begin(0) <= byte_pointer && m.end(0) > byte_pointer
          return { start: m.begin(0), end: m.end(0), value: m[0][2..].to_i(2) }
        elsif m.begin(0) > byte_pointer
          return { start: m.begin(0), end: m.end(0), value: m[0][2..].to_i(2) }
        end
        pos = m.end(0)
      end
      nil
    end

    private def replace_number(line, start_byte, end_byte, new_value, kind)
      formatted = case kind
                  when :hex
                    width = (end_byte - start_byte) - 2
                    '0x' + new_value.to_s(16).rjust(width, '0')
                  when :bin
                    width = (end_byte - start_byte) - 2
                    '0b' + new_value.to_s(2).rjust(width, '0')
                  end
      before = line.byteslice(0, start_byte)
      after = line.byteslice(end_byte, line.bytesize - end_byte)
      @buffer_of_lines[@line_index] = String.new(before + formatted + after, encoding: encoding)
      @byte_pointer = (before + formatted).bytesize - 1
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
      equalize_windows if @settings.get(:equalalways)
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
      cap_undo_history
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

    private def cap_undo_history
      cap = @settings.get(:undolevels).to_i
      return if cap <= 0
      return unless @undo_redo_history.is_a?(Array)
      return if @undo_redo_history.size <= cap

      drop = @undo_redo_history.size - cap
      @undo_redo_history = @undo_redo_history.last(cap)
      @undo_redo_index = [@undo_redo_index - drop, 0].max
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

      if @modified && !@settings.get(:hidden) && !@settings.get(:autowrite)
        @status_message = 'E37: No write since last change (add ! to override)'
        return
      end
      autowrite_if_modified

      idx = @buffer_order.index(@current_buffer.id) || 0
      target_id = @buffer_order[(idx + direction) % @buffer_order.size]
      swap_to_buffer(@buffers[target_id])
    end

    def autowrite_if_modified
      return unless @settings.get(:autowrite)
      return unless @current_buffer && @modified
      return unless @filepath

      save
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

    def backup_path(target)
      ext = @settings.get(:backupext).to_s
      ext = '~' if ext.empty?
      dir = @settings.get(:backupdir).to_s
      dir = '.' if dir.empty?

      basename = File.basename(target.to_s) + ext
      if dir == '.'
        # Vim's '.' means alongside the file
        File.join(File.dirname(target.to_s), basename)
      else
        FileUtils.mkdir_p(File.expand_path(dir))
        File.join(File.expand_path(dir), basename)
      end
    end

    def save(path = nil)
      target = path || @filepath
      raise 'no file path' unless target

      @autocommands&.fire(:bufwritepre, target.to_s, self)
      keep_backup = @settings.get(:backup)
      writebackup = @settings.get(:writebackup)
      backup = nil
      if (keep_backup || writebackup) && File.exist?(target)
        backup = backup_path(target)
        FileUtils.cp(target, backup)
      end
      ff = @current_buffer&.fileformat || @settings.get(:fileformat) || 'unix'
      sep = case ff
            when 'dos' then "\r\n"
            when 'mac' then "\r"
            else "\n"
            end
      enc = @settings.get(:fileencoding).to_s
      enc = 'utf-8' if enc.empty?
      # fixendofline forces a trailing separator regardless of endofline.
      add_eol = @settings.get(:fixendofline) || @settings.get(:endofline)
      content = @buffer_of_lines.join(sep)
      content += sep if add_eol
      content = content.encode(enc, invalid: :replace, undef: :replace) if enc.downcase != 'utf-8'
      File.binwrite(target, content)
      @filepath = target
      @modified = false
      # Successful write: remove the transient writebackup if backup setting
      # didn't ask us to keep it.
      if backup && !keep_backup
        File.delete(backup) if File.exist?(backup)
      end
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
      return if @settings.get(:lazyredraw) && @replaying

      @screen&.render
    end

    def update(key)
      # Any keypress dismisses an open hover popup. Cleared first so the
      # *next* render-loop tick won't show it; the key dispatched below
      # is processed normally.
      @hover_popup = nil if @hover_popup

      if @prompt_mode == :listing
        process_listing_key(key)
        return
      end

      if @confirm_question
        handle_confirm_key(key)
        return
      end

      if mouse_event?(key)
        handle_mouse_event(key)
        return
      end

      if @digraph_pending
        capture_digraph_key(key)
        return
      end

      if @completion_chain_pending
        @completion_chain_pending = false
        case key.char
        when "\x06" then start_completion_with_source(:filenames, +1)
        when "\x0B" then start_completion_with_source(:dictionary, +1)
        when "\x0C" then start_completion_with_source(:lines, +1)
        else
          @status_message = 'unknown completion source'
        end
        return
      end

      if @completion_active && !completion_key?(key)
        cancel_completion
      end

      if @rvim_pending_op
        action = preprocess_pending_op_key(key)
        case action
        when :handled then return
        when :handed_off then return
        when :digit_count
          # Accumulate count for the motion (e.g. d3w). Forward the digit to
          # Reline's argument accumulator without consuming the pending op.
          super
          return
        when :dispatch_motion
          pre = [@line_index, @byte_pointer]
          pre_buffer = @buffer_of_lines.map(&:dup)
          op = @rvim_pending_op
          @rvim_pending_op = nil
          inclusive = inclusive_motion_key?(key)
          hint_linewise = linewise_motion?(key)
          dispatch_motion_for_op(key)
          post = [@line_index, @byte_pointer]
          kind = (hint_linewise || lines_only_motion?(pre, post, hint_linewise)) ? :line : :char
          apply_op_to_range(op, pre, post, kind: kind, inclusive: inclusive)
          # We bypass Reline's input_key, so push undo manually when the
          # operator mutated the buffer. Yank doesn't change the buffer
          # but the snapshot still gets compared, so this is uniform.
          if pre_buffer != @buffer_of_lines
            push_undo_redo(true)
          end
          sync_current_buffer_lines
          return
        end
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

      if @rvim_pending_format_op
        # 'gqq' = current line; otherwise capture motion.
        ch = key.char
        if ch == 'q'
          @rvim_pending_format_op = false
          apply_format_to_lines(@line_index, @line_index)
          return
        end

        pre = [@line_index, @byte_pointer]
        @rvim_pending_format_op = false
        super
        post = [@line_index, @byte_pointer]
        start_line, end_line = [pre[0], post[0]].minmax
        apply_format_to_lines(start_line, end_line)
        return
      end

      if @rvim_pending_filter_op
        # '!!' = current line; otherwise capture motion and prefill ex prompt.
        ch = key.char
        if ch == '!'
          @rvim_pending_filter_op = false
          start_filter_prompt(@line_index, @line_index)
          return
        end

        pre = [@line_index, @byte_pointer]
        @rvim_pending_filter_op = false
        super
        post = [@line_index, @byte_pointer]
        start_line, end_line = [pre[0], post[0]].minmax
        start_filter_prompt(start_line, end_line)
        return
      end

      if @rvim_pending_equal_op
        ch = key.char
        if ch == '='
          @rvim_pending_equal_op = false
          apply_equal_to_lines(@line_index, @line_index)
          return
        end

        pre = [@line_index, @byte_pointer]
        @rvim_pending_equal_op = false
        super
        post = [@line_index, @byte_pointer]
        start_line, end_line = [pre[0], post[0]].minmax
        apply_equal_to_lines(start_line, end_line)
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
          extend_visual_cursor_past_eol_if(key)
        end
      elsif @rvim_text_object_pending
        consume_text_object_key(key)
      elsif operator_pending? && text_object_prefix?(key)
        @rvim_text_object_pending = key.char == 'a' ? :around : :inner
      elsif @replace_mode && editing_mode_label == :vi_insert && replace_mode_self_insert?(key)
        ch = key.char.is_a?(Integer) ? key.char.chr : key.char.to_s
        if ch == "\b" || ch == "\x7F" # Backspace / DEL
          replace_undo_at_cursor
        else
          replace_overwrite_at_cursor(ch)
        end
      else
        @status_message = nil
        super
        @modified = true if pre_buffer != @buffer_of_lines
        maybe_expand_insert_abbreviation(key)
      end

      sync_current_buffer_lines
      capture_special_marks(pre_buffer, pre_mode)
      freeze_change_if_settled(pre_buffer) unless @replaying
      update_signature_popup(key, pre_mode)
    end

    # Auto-trigger signatureHelp on `(` and `,`; dismiss on `)` or any
    # mode change away from vi_insert. Runs AFTER super so the char
    # has already been inserted (cursor sits past the char), giving the
    # server the right position to compute the active parameter.
    private def update_signature_popup(key, _pre_mode)
      ch = key.char
      ch_str = ch.is_a?(Integer) ? ch.chr : ch.to_s

      if @signature_popup && editing_mode_label != :vi_insert
        @signature_popup = nil
        return
      end

      if @signature_popup && ch_str == ')'
        @signature_popup = nil
        return
      end

      if editing_mode_label == :vi_insert && (ch_str == '(' || ch_str == ',')
        lsp_show_signature_help(position_offset: -1)
      end
    rescue StandardError
      # Insert-mode auto-trigger must never crash the editor — swallow
      # any unexpected LSP / parse failure and keep typing usable.
      @signature_popup = nil
    end

    # Reline's move_undo_redo replaces @buffer_of_lines with a new array
    # reference. Our current_buffer.lines may still point to the old (now
    # mutated) array. Re-bind so the screen renders the same content the
    # editor logic sees.
    private def sync_current_buffer_lines
      return unless @current_buffer

      if @current_buffer.lines.object_id != @buffer_of_lines.object_id
        @current_buffer.lines = @buffer_of_lines
      end
    end

    MAXMAPDEPTH = 1000

    private def mapping_eligible?
      return false if @map_noremap_active
      return false if @replaying
      return false if @list_view
      return false if @waiting_proc
      return false if @rvim_text_object_pending
      return false if @rvim_visual_textobj_pending
      return false if @prompt_mode == :listing

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
      return :cmdline if @prompt_mode == :ex || @prompt_mode == :search_forward || @prompt_mode == :search_backward
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

      saved_status = @status_message if mapping.silent
      begin
        if mapping.callback
          mapping.callback.call
        elsif mapping.recursive
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
        @status_message = saved_status if mapping.silent
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
        @replace_mode = false
        @replace_originals = nil
        finalize_block_insert
        @autocommands&.fire(:insertleave, @filepath.to_s, self)
      elsif pre_mode == :vi_command && cur_mode == :vi_insert
        @autocommands&.fire(:insertenter, @filepath.to_s, self)
      end
    end

    private def maybe_expand_insert_abbreviation(key)
      return if @abbreviations.nil? || @abbreviations.empty?(:insert)
      return unless editing_mode_label == :vi_insert
      return if @prompt_mode

      ch = key.char
      return if ch.nil?

      ch_str = ch.is_a?(Integer) ? ch.chr : ch.to_s
      return unless word_terminator?(ch_str)

      line = @buffer_of_lines[@line_index] || ''
      detection = @abbreviations.detect(line, @byte_pointer, :insert)
      return unless detection

      word_start, word_end, entry = detection
      head = line.byteslice(0, word_start) || +''
      tail = line.byteslice(word_end, line.bytesize - word_end) || +''
      @buffer_of_lines[@line_index] = String.new(head + entry.rhs + tail, encoding: encoding)
      @byte_pointer = word_start + entry.rhs.bytesize + (line.bytesize - word_end)
      @modified = true
    end

    private def word_terminator?(ch_str)
      return false if ch_str.empty?

      ch_str !~ /[A-Za-z0-9_]/
    end

    def expand_abbreviation_in_buffer(buf, mode)
      return buf if @abbreviations.nil? || @abbreviations.empty?(mode)

      detection = @abbreviations.detect(buf, buf.bytesize, mode)
      return buf unless detection

      word_start, word_end, entry = detection
      head = buf.byteslice(0, word_start) || +''
      tail = buf.byteslice(word_end, buf.bytesize - word_end) || +''
      head + entry.rhs + tail
    end

    private def replace_mode_self_insert?(key)
      ch = key.char
      return false if ch.nil?

      ch_str = ch.is_a?(Integer) ? ch.chr : ch.to_s
      return true if ch_str == "\b" || ch_str == "\x7F"

      # Single printable char (not Esc, not control except handled bsp).
      ch_str.bytes.size >= 1 && (ch_str.bytes.first >= 0x20 && ch_str.bytes.first != 0x7F)
    end

    attr_reader :replace_mode

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

    private def sol_byte_for(line_index)
      return 0 unless @settings.get(:startofline)

      line = @buffer_of_lines[line_index] || ''
      first_non_whitespace_col(line)
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
    # NeoVim allows the cursor to sit one past the last char of the line in
    # visual character mode (so $ extends the selection through the newline
    # position). Reline's vi-mode dispatch unconditionally clamps the cursor
    # back onto the last byte after every command. Undo that clamp for the
    # specific commands where vim's visual mode keeps the cursor at EOL.
    private def extend_visual_cursor_past_eol_if(key)
      return unless @visual_mode == :char || @visual_mode == :block

      ch = key.char
      ch_str = ch.is_a?(Integer) ? ch.chr : ch.to_s
      return unless ch_str == '$'

      line = @buffer_of_lines[@line_index] || ''
      @byte_pointer = line.bytesize
    end

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
      when 'I', 'A'
        sel = selection
        return true unless sel

        if @visual_mode == :block
          start_block_insert(sel, append: ch == 'A')
        else
          start_line = sel.start_line
          col = ch == 'I' ? sol_byte_for(start_line) : (@buffer_of_lines[start_line] || '').bytesize
          exit_visual
          @line_index = start_line
          @byte_pointer = col
          @config.editing_mode = :vi_insert
        end
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
      when '!'
        sel = selection
        exit_visual
        if sel
          start_filter_prompt(sel.start_line, sel.end_line)
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
      # When 'clipboard' includes 'unnamedplus', mirror unnamed yanks to the
      # system clipboard register too.
      if register.nil? && @settings.get(:clipboard).to_s.split(',').include?('unnamedplus')
        Rvim::SystemClipboard.write(text.is_a?(Array) ? text.join("\n") : text.to_s)
      end
    end

    def read_register(name = nil)
      n = name || '"'
      if n == '+' || (name.nil? && clipboard_aliases_unnamed?)
        # Vim's `clipboard=unnamedplus` aliases the unnamed register (`"`)
        # to the system clipboard for both write AND read, so `p` pastes
        # whatever was last copied externally.
        text = Rvim::SystemClipboard.read.to_s
        kind = text.end_with?("\n") ? :line : :char
        return Rvim::RegisterEntry.new(text.chomp, kind)
      end
      if n == '%'
        return Rvim::RegisterEntry.new(@filepath.to_s, :char)
      end
      @registers.read(n)
    end

    private def clipboard_aliases_unnamed?
      cb = @settings.get(:clipboard).to_s.split(',')
      cb.include?('unnamedplus') || cb.include?('unnamed')
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

    private def start_block_insert(sel, append:)
      start_line = sel.start_line
      end_line = sel.end_line
      # Pick the leftmost column for I, the rightmost+1 for A — matches vim.
      cols = (start_line..end_line).map { |li| (@buffer_of_lines[li] || '').bytesize }
      col = if append
              # Use the right edge of the selection, clamped to each line's
              # length when applied later.
              [sel.start_col, sel.end_col].max + 1
            else
              [sel.start_col, sel.end_col].min
            end

      original_lines = (start_line..end_line).each_with_object({}) do |li, h|
        h[li] = (@buffer_of_lines[li] || '').dup
      end

      @block_insert_state = {
        start_line: start_line,
        end_line: end_line,
        col: col,
        append: append,
        original_lines: original_lines,
      }

      exit_visual
      @line_index = start_line
      @byte_pointer = [col, (@buffer_of_lines[start_line] || '').bytesize].min
      @config.editing_mode = :vi_insert
    end

    private def finalize_block_insert
      state = @block_insert_state
      return unless state

      @block_insert_state = nil
      first_line = @buffer_of_lines[state[:start_line]] || ''
      original_first = state[:original_lines][state[:start_line]] || ''
      delta = first_line.bytesize - original_first.bytesize
      return if delta <= 0

      col = state[:col]
      inserted = first_line.byteslice(col, delta)
      return if inserted.nil? || inserted.empty?

      ((state[:start_line] + 1)..state[:end_line]).each do |li|
        line = @buffer_of_lines[li] || +''
        # When append is true, the cursor was at end-of-line in the start line;
        # for shorter lines, append at end-of-line; for longer lines, splice in.
        target_col = [col, line.bytesize].min
        head = line.byteslice(0, target_col).to_s
        tail = line.byteslice(target_col, line.bytesize - target_col).to_s
        @buffer_of_lines[li] = String.new(head + inserted + tail, encoding: encoding)
      end
      sync_current_buffer_lines
      @modified = true
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

      # If we entered a CSI-consume state during a paste burst, keep
      # eating bytes until the sequence terminator — even after the
      # paste has technically ended. The terminator byte of the closing
      # bracketed-paste marker (\e[201~) arrives AFTER in_pasting?
      # flips to false, so this check has to live outside the paste
      # branch below.
      if @cmdline_paste_consuming_csi && ch.is_a?(String)
        clear_cmdline_completion
        @cmdline_paste_consuming_csi = false if ch =~ /\A[A-Za-z~]\z/
        clear_history_cursor
        return
      end

      # Mid-paste keys arrive as part of a contiguous burst that Reline's
      # IOGate flags as `in_pasting?`. Treat newlines / esc / tab as
      # literal so a multi-line clipboard paste lands in the cmdline as
      # a single line without prematurely executing or cancelling, and
      # drop control chars / escape sequences entirely so they don't
      # leave invisible bytes in the prompt buffer (which would push
      # the cursor past the visible text).
      if pasting_prompt_key? && ch.is_a?(String)
        clear_cmdline_completion
        if ch == "\e"
          # Start of a multi-byte escape sequence whose remaining bytes
          # will arrive as separate keys — enter consume mode.
          @cmdline_paste_consuming_csi = true
        elsif printable_paste_char?(ch)
          @prompt_buffer << ch
        end
        clear_history_cursor
        return
      end

      if ch.is_a?(String) && ch.bytesize > 1 && ch.start_with?("\e")
        handle_prompt_escape_sequence(key)
        return
      end

      if ch == "\t" && @prompt_mode == :ex
        cmdline_complete(+1)
        return
      end

      if ch == "\x19" && @prompt_mode == :ex
        # Ctrl-Y on some terminals: skip; reserved
      end

      case ch
      when "\r", "\n"
        clear_cmdline_completion
        execute_prompt
        return
      when "\e"
        clear_cmdline_completion
        cancel_prompt
        return
      when "\x7f", "\b" # backspace / DEL
        clear_cmdline_completion
        if @prompt_buffer.empty?
          cancel_prompt
          return
        else
          @prompt_buffer.chop!
        end
        clear_history_cursor
      else
        clear_cmdline_completion
        @prompt_buffer << ch.to_s
        clear_history_cursor
        maybe_expand_cmdline_abbreviation(ch.to_s) if @prompt_mode == :ex
      end
      refresh_incremental_search
    end

    # True when the editor's main loop has flagged a paste burst on the
    # current key. @in_pasting is set by Reline::LineEditor#set_pasting_state,
    # which the run loop calls each iteration with Reline::IOGate.in_pasting?.
    # We read the ivar directly rather than re-querying IOGate so unit
    # tests (which don't go through the run loop) see the default false.
    private def pasting_prompt_key?
      @in_pasting ? true : false
    end

    # Filter for chars that may be appended to the prompt buffer during
    # a paste burst. Drops CR/LF (would prematurely execute), all C0
    # control chars (most notably ESC), and any multi-byte escape
    # sequence (bracketed-paste markers, arrow keys embedded in pasted
    # terminal output, etc.). Single-byte printable chars and printable
    # multi-byte UTF-8 chars pass through.
    private def printable_paste_char?(ch)
      return false if ch.empty?
      return false if ch.start_with?("\e")
      if ch.bytesize == 1
        b = ch.getbyte(0)
        # Allow tab so pasted indentation survives; drop everything
        # else below space (0x20) and DEL (0x7f).
        return false if b < 0x20 && b != 0x09
        return false if b == 0x7f
      end
      true
    end

    private def maybe_expand_cmdline_abbreviation(ch)
      return if @abbreviations.nil? || @abbreviations.empty?(:cmdline)
      return unless word_terminator?(ch)

      detection = @abbreviations.detect(@prompt_buffer, @prompt_buffer.bytesize, :cmdline)
      return unless detection

      word_start, word_end, entry = detection
      head = @prompt_buffer.byteslice(0, word_start) || +''
      tail = @prompt_buffer.byteslice(word_end, @prompt_buffer.bytesize - word_end) || +''
      @prompt_buffer = +(head + entry.rhs + tail)
    end

    private def cmdline_complete(direction)
      return unless @prompt_mode == :ex

      if @cmdline_popup && !@cmdline_popup.empty?
        new_idx = (@cmdline_popup.pointer + direction) % @cmdline_popup.size
        @cmdline_popup.pointer = new_idx
        apply_cmdline_completion
        return
      end

      ctx = Rvim::CmdlineCompletion.analyze(@prompt_buffer)
      candidates = Rvim::CmdlineCompletion.candidates(ctx, self)
      return if candidates.empty?

      @cmdline_completion_context = ctx
      @cmdline_popup = Rvim::CompletionPopup.new(contents: candidates, pointer: direction < 0 ? candidates.size - 1 : 0, max_height: configured_pum_height)
      apply_cmdline_completion
    end

    private def apply_cmdline_completion
      ctx = @cmdline_completion_context
      return unless ctx

      candidate = @cmdline_popup.contents[@cmdline_popup.pointer].to_s
      @prompt_buffer = +"#{ctx.prefix}#{candidate}"
    end

    private def clear_cmdline_completion
      @cmdline_popup = nil
      @cmdline_completion_context = nil
    end

    attr_reader :cmdline_popup

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
      max = @settings.get(:history).to_i
      max = EX_HISTORY_MAX if max <= 0
      @ex_history.shift while @ex_history.size > max
    end

    private def refresh_incremental_search
      return unless @prompt_mode == :search_forward || @prompt_mode == :search_backward
      return unless @settings.get(:incsearch)

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
      when :ex_input
        # Each Enter in :ex_input mode appends a line to the collector.
        # A single '.' on its own line ends input.
        if @prompt_buffer == '.'
          @prompt_buffer = +''
          commit_ex_input
        else
          append_ex_input_line(@prompt_buffer)
          @prompt_buffer = +''
        end
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
      target = Rvim::Search.next_match(matches, @line_index, @byte_pointer, direction, wrapscan: @settings.get(:wrapscan))
      if target
        push_jump
        move_cursor_to(target[0], target[1])
      else
        @status_message = "E385: Search hit BOTTOM without match for: #{word}"
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
      target = Rvim::Search.next_match(@search_matches, @line_index, @byte_pointer, direction, wrapscan: @settings.get(:wrapscan))
      if target
        push_jump
        move_cursor_to(target[0], target[1])
      elsif @settings.get(:wrapscan)
        @status_message = "E486: Pattern not found: #{@search_pattern}"
      else
        @status_message = direction == :forward ? "E385: Search hit BOTTOM without match for: #{@search_pattern}" : "E384: Search hit TOP without match for: #{@search_pattern}"
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
      @byte_pointer = sol_byte_for(@line_index)
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

    # Classify a single character (which may be multibyte). Vim's word
    # motion treats different Unicode blocks as separate word groups, so
    # 'abc' (Latin) and 'あいう' (Hiragana) are distinct classes — 'w'
    # stops at a script change. With `big: true` (for W/B/E motions) the
    # only word boundary is whitespace, matching vim.
    private def word_class(mbchar, big)
      return :space if mbchar.nil? || mbchar.empty?

      first = mbchar.getbyte(0)
      return :space if first == 0x20 || first == 0x09 # space / tab
      return :word if big

      if first < 0x80
        mbchar =~ /\w/ ? :word : :punct
      else
        cp =
          begin
            mbchar.codepoints.first
          rescue ArgumentError, Encoding::UndefinedConversionError
            nil
          end
        return :other_mbword if cp.nil?

        case cp
        when 0x3040..0x309F then :hiragana
        when 0x30A0..0x30FF then :katakana
        when 0x4E00..0x9FFF, 0x3400..0x4DBF then :cjk_ideograph
        when 0xFF00..0xFFEF then :halfwidth
        when 0x3000..0x303F then :cjk_punct
        when 0x00A0..0x024F then :latin_extended
        when 0x0400..0x04FF then :cyrillic
        when 0x0370..0x03FF then :greek
        when 0xAC00..0xD7AF then :hangul
        else :other_mbword
        end
      end
    end

    private def mbchar_at(line, pos)
      return nil if pos >= line.bytesize

      size = Reline::Unicode.get_next_mbchar_size(line, pos)
      size = 1 if size <= 0
      line.byteslice(pos, size)
    end

    private def mbchar_size_forward(line, pos)
      return 1 if pos >= line.bytesize

      size = Reline::Unicode.get_next_mbchar_size(line, pos)
      size > 0 ? size : 1
    end

    private def prev_mbchar_at(line, pos)
      return nil if pos <= 0

      size = Reline::Unicode.get_prev_mbchar_size(line, pos)
      size = 1 if size <= 0
      line.byteslice(pos - size, size)
    end

    private def mbchar_size_backward(line, pos)
      return 1 if pos <= 0

      size = Reline::Unicode.get_prev_mbchar_size(line, pos)
      size > 0 ? size : 1
    end

    private def advance_word_start(big:)
      line = @buffer_of_lines[@line_index] || ''
      # Step over the current run (same character class).
      cur_class = word_class(mbchar_at(line, @byte_pointer), big)
      while @byte_pointer < line.bytesize &&
            word_class(mbchar_at(line, @byte_pointer), big) == cur_class && cur_class != :space
        @byte_pointer += mbchar_size_forward(line, @byte_pointer)
      end
      # Now skip whitespace (including line breaks) until we find a non-space.
      loop do
        line = @buffer_of_lines[@line_index] || ''
        while @byte_pointer < line.bytesize && word_class(mbchar_at(line, @byte_pointer), big) == :space
          @byte_pointer += mbchar_size_forward(line, @byte_pointer)
        end
        return true if @byte_pointer < line.bytesize

        if @line_index + 1 < @buffer_of_lines.size
          @line_index += 1
          @byte_pointer = 0
          return true if (@buffer_of_lines[@line_index] || '').empty?
        else
          last = @buffer_of_lines[@line_index] || ''
          @byte_pointer = [last.bytesize - last_mbchar_size(last), 0].max
          return false
        end
      end
    end

    private def retreat_word_start(big:)
      if @byte_pointer.zero?
        return false if @line_index.zero?

        @line_index -= 1
        prev = @buffer_of_lines[@line_index] || ''
        @byte_pointer = prev.bytesize
      end
      line = @buffer_of_lines[@line_index] || ''
      while @byte_pointer > 0 && word_class(prev_mbchar_at(line, @byte_pointer), big) == :space
        @byte_pointer -= mbchar_size_backward(line, @byte_pointer)
      end
      return retreat_word_start(big: big) if @byte_pointer.zero?

      cls = word_class(prev_mbchar_at(line, @byte_pointer), big)
      while @byte_pointer > 0 && word_class(prev_mbchar_at(line, @byte_pointer), big) == cls
        @byte_pointer -= mbchar_size_backward(line, @byte_pointer)
      end
      true
    end

    private def advance_word_end(big:)
      line = @buffer_of_lines[@line_index] || ''
      # Step forward one mbchar to escape the current word-end.
      step = mbchar_size_forward(line, @byte_pointer)
      if @byte_pointer + step < line.bytesize
        @byte_pointer += step
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
        while @byte_pointer < line.bytesize && word_class(mbchar_at(line, @byte_pointer), big) == :space
          @byte_pointer += mbchar_size_forward(line, @byte_pointer)
        end
        break if @byte_pointer < line.bytesize
        return false if @line_index + 1 >= @buffer_of_lines.size

        @line_index += 1
        @byte_pointer = 0
      end
      # Advance through the current run; stop on the LAST char (not past it).
      cls = word_class(mbchar_at(line, @byte_pointer), big)
      loop do
        next_step = mbchar_size_forward(line, @byte_pointer)
        next_pos = @byte_pointer + next_step
        break if next_pos >= line.bytesize
        break if word_class(mbchar_at(line, next_pos), big) != cls

        @byte_pointer = next_pos
      end
      true
    end

    private def rvim_g_prefix(key, arg: nil)
      saved_arg = arg
      @waiting_proc = lambda do |key_for_proc, _sym|
        @waiting_proc = nil
        case key_for_proc
        when 'g', 'g'.ord
          # [count]gg jumps to line [count] (1-based; default first line).
          target = saved_arg.is_a?(Integer) && saved_arg > 0 ? saved_arg - 1 : 0
          target = target.clamp(0, [@buffer_of_lines.size - 1, 0].max)
          push_jump
          @line_index = target
          @byte_pointer = sol_byte_for(@line_index)
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
        when 'r', 'r'.ord
          lsp_find_references
        when 'j', 'j'.ord
          display_line_motion(:down)
        when 'k', 'k'.ord
          display_line_motion(:up)
        when 'q', 'q'.ord
          start_format_op
        end
      end
    end

    private def start_format_op
      @rvim_pending_format_op = true
    end

    private def rvim_filter_operator(key, arg: 1)
      @rvim_pending_filter_op = true
    end

    private def rvim_equal_operator(key, arg: 1)
      @rvim_pending_equal_op = true
    end

    def apply_equal_to_lines(start_line, end_line)
      lo = start_line.clamp(0, [@buffer_of_lines.size - 1, 0].max)
      hi = end_line.clamp(0, [@buffer_of_lines.size - 1, 0].max)
      lines = @buffer_of_lines[lo..hi].map(&:to_s)
      prg = @settings.get(:equalprg).to_s
      return if prg.empty?

      result = Rvim::Filter.run(prg, input: lines.join("\n"), shell: @settings.get(:shell), shellcmdflag: @settings.get(:shellcmdflag))
      if result.success?
        out_lines = result.stdout.chomp("\n").split("\n", -1)
        replace_line_range(lo, hi, out_lines)
      else
        @status_message = "equalprg: #{result.stderr.lines.first&.chomp || 'failed'}"
      end
    end

    attr_reader :confirm_question, :confirm_options

    def confirm_prompt(question, options, &block)
      @confirm_question = question.to_s
      @confirm_options = Array(options).map { |o| o.to_s.downcase }
      @confirm_callback = block
    end

    private def handle_confirm_key(key)
      ch = key.char.to_s
      if ch == "\e" || ch == "\x03"
        cancel_confirm_prompt
        return
      end

      norm = ch.downcase
      return unless @confirm_options&.include?(norm)

      cb = @confirm_callback
      cancel_confirm_prompt
      cb&.call(norm)
    end

    def cancel_confirm_prompt
      @confirm_question = nil
      @confirm_options = nil
      @confirm_callback = nil
    end

    MOUSE_SGR_RE = /\A\e\[<(\d+);(\d+);(\d+)([Mm])\z/

    private def mouse_event?(key)
      return false if @settings.get(:mouse).to_s.empty?
      return false unless key.char.is_a?(String)

      key.char.match?(MOUSE_SGR_RE)
    end

    private def handle_mouse_event(key)
      m = MOUSE_SGR_RE.match(key.char)
      return unless m

      button = m[1].to_i
      col = m[2].to_i
      row = m[3].to_i
      press = m[4] == 'M'

      case button
      when 0
        mouse_left_click(col, row) if press
      when 64
        scroll_via_mouse(-3)
      when 65
        scroll_via_mouse(+3)
      end
    end

    private def mouse_left_click(col, row)
      win = window_at(row, col)
      return unless win

      activate_window(win) if win != @current_window

      buffer_line = win.scroll_top + (row - win.row - 1)
      buffer_line = buffer_line.clamp(0, [@buffer_of_lines.size - 1, 0].max)
      @line_index = buffer_line

      gw = @screen ? @screen.gutter_width_for(win.buffer) : 0
      target_byte = col - win.col - gw - 1
      line = @buffer_of_lines[@line_index] || ''
      @byte_pointer = target_byte.clamp(0, [line.bytesize - 1, 0].max)
    end

    private def window_at(row, col)
      @windows.find do |w|
        row > w.row && row <= w.row + w.height &&
          col > w.col && col <= w.col + w.width
      end
    end

    private def scroll_via_mouse(delta)
      return unless @current_window

      content_rows = [@current_window.height - 1, 1].max
      step = delta.abs.clamp(1, content_rows)
      direction = delta.positive? ? +1 : -1
      target = (@line_index + step * direction).clamp(0, [@buffer_of_lines.size - 1, 0].max)
      return if target == @line_index

      @line_index = target
      target_line = @buffer_of_lines[@line_index] || ''
      @byte_pointer = @byte_pointer.clamp(0, [target_line.bytesize - 1, 0].max)
    end

    private def rvim_tilde(key, arg: 1)
      if @settings.get(:tildeop)
        start_case_op(:toggle, arg)
      else
        toggle_case_at_cursor
      end
    end

    private def toggle_case_at_cursor
      line = @buffer_of_lines[@line_index] || ''
      return if line.empty?

      bp = [@byte_pointer, line.bytesize - 1].min
      ch = line.byteslice(bp, 1)
      flipped = if ch =~ /[A-Z]/
                  ch.downcase
                elsif ch =~ /[a-z]/
                  ch.upcase
                else
                  ch
                end
      head = line.byteslice(0, bp)
      tail = line.byteslice(bp + 1, line.bytesize - bp - 1) || +''
      @buffer_of_lines[@line_index] = String.new(head + flipped + tail, encoding: encoding)
      @byte_pointer = (bp + 1).clamp(0, line.bytesize - 1)
      @modified = true
    end

    private def rvim_keyword_lookup(key, arg: 1)
      # Prefer LSP textDocument/hover when an LSP client is available;
      # falls through to the external keywordprg (default `man <word>`)
      # otherwise.
      return if lsp_show_hover

      word = word_at_cursor
      unless word
        @status_message = 'E348: No string under cursor'
        return
      end

      prg = @settings.get(:keywordprg).to_s
      prg = 'man' if prg.empty?
      result = Rvim::Filter.run("#{prg} #{word}", shell: @settings.get(:shell), shellcmdflag: @settings.get(:shellcmdflag))
      if result.success?
        lines = result.stdout.lines.map(&:chomp)
        lines = ['(no output)'] if lines.empty?
        show_list(lines)
      else
        msg = result.stderr.lines.first&.chomp || "exit #{result.status.exitstatus}"
        @status_message = "K: #{msg}"
      end
    end

    def apply_format_to_lines(start_line, end_line)
      width = @settings.get(:textwidth).to_i
      width = 78 if width <= 0

      lo = start_line.clamp(0, [@buffer_of_lines.size - 1, 0].max)
      hi = end_line.clamp(0, [@buffer_of_lines.size - 1, 0].max)
      lines = @buffer_of_lines[lo..hi].map(&:to_s)

      formatprg = @settings.get(:formatprg).to_s
      reformatted = if formatprg.empty?
                      Rvim::Reformat.wrap(lines, width)
                    else
                      result = Rvim::Filter.run(formatprg, input: lines.join("\n"), shell: @settings.get(:shell), shellcmdflag: @settings.get(:shellcmdflag))
                      if result.success?
                        result.stdout.chomp("\n").split("\n", -1)
                      else
                        @status_message = "formatprg: #{result.stderr.lines.first&.chomp || 'failed'}"
                        return
                      end
                    end
      replace_line_range(lo, hi, reformatted)
    end

    # Ex-mode line input: :a / :i / :c. Each one switches to a new prompt
    # that captures lines until the user types a single '.' on a line by
    # itself (vim convention). Then:
    #   :append (a)  — insert collected lines AFTER the target line
    #   :insert (i)  — insert collected lines BEFORE the target line
    #   :change (c)  — replace the target range with the collected lines
    def start_ex_input(kind, range: nil, line_number: nil)
      target_start, target_end = resolve_ex_input_range(range, line_number)
      @ex_input_state = {
        kind: kind,
        start_line: target_start,
        end_line: target_end,
        lines: [],
      }
      @prompt_mode = :ex_input
      @prompt_buffer = +''
      @status_message = "-- #{kind.to_s.upcase} -- (end with a single '.')"
    end

    private def resolve_ex_input_range(range, line_number)
      if line_number
        idx = line_number - 1
        return [idx, idx]
      end
      if range
        first, last = ex_range_to_indices(range)
        return [first, last]
      end
      [@line_index, @line_index]
    end

    private def ex_range_to_indices(range)
      buf_size = @buffer_of_lines.size
      case range
      when :whole then [0, buf_size - 1]
      when :current then [@line_index, @line_index]
      when :visual
        if @last_visual
          a = @last_visual[:anchor].first
          b = @last_visual[:last_end].first
          [[a, b].min, [a, b].max]
        else
          [@line_index, @line_index]
        end
      when Array then [range[0] - 1, range[1] - 1]
      when Hash
        first = ex_addr_to_index(range[:start]) || @line_index
        last = ex_addr_to_index(range[:end]) || first
        [first, last]
      when Integer then [range - 1, range - 1]
      else [@line_index, @line_index]
      end
    end

    private def ex_addr_to_index(addr)
      case addr
      when nil then nil
      when '$' then @buffer_of_lines.size - 1
      when '.' then @line_index
      when /\A\d+\z/ then addr.to_i - 1
      when Integer then addr - 1
      end
    end

    def commit_ex_input
      state = @ex_input_state
      return reset_prompt unless state

      lines = state[:lines]
      target_start = state[:start_line]
      target_end = state[:end_line]

      case state[:kind]
      when :append
        @buffer_of_lines.insert(target_start + 1, *lines)
        @line_index = target_start + lines.size
      when :insert
        @buffer_of_lines.insert(target_start, *lines)
        @line_index = target_start + lines.size - 1
        @line_index = target_start if lines.empty?
      when :change
        @buffer_of_lines[target_start..target_end] = lines.empty? ? [String.new('', encoding: encoding)] : lines
        @line_index = target_start + [lines.size - 1, 0].max
      end
      @line_index = [@line_index, @buffer_of_lines.size - 1].min
      @line_index = 0 if @line_index.negative?
      @byte_pointer = 0
      @modified = true unless lines.empty? && state[:kind] == :append
      @ex_input_state = nil
      @prompt_mode = nil
      @prompt_buffer = +''
      @status_message = nil
      sync_current_buffer_lines
    end

    def append_ex_input_line(text)
      state = @ex_input_state
      return unless state

      state[:lines] << String.new(text.to_s, encoding: encoding)
    end

    attr_reader :ex_input_state

    def start_filter_prompt(start_line, end_line)
      lo = start_line + 1
      hi = end_line + 1
      @prompt_mode = :ex
      @prompt_buffer = +"#{lo},#{hi}!"
      @status_message = nil
      clear_history_cursor
    end

    def display_line_motion(direction)
      unless @settings.get(:wrap) && @screen && @current_window
        plain_line_step(direction)
        return
      end

      width = @screen.content_width_for(@current_window)
      target = Rvim::DisplayMotion.next_position(
        @buffer_of_lines,
        @line_index,
        @byte_pointer,
        width,
        direction,
        splitter: ->(line, w) { @screen.split_segments_public(line, w) },
      )
      if target
        @line_index, @byte_pointer = target
      else
        plain_line_step(direction)
      end
    end

    private def plain_line_step(direction)
      if direction == :down
        return if @line_index >= @buffer_of_lines.size - 1

        @line_index += 1
      else
        return if @line_index <= 0

        @line_index -= 1
      end
      target = @buffer_of_lines[@line_index] || ''
      @byte_pointer = @byte_pointer.clamp(0, [target.bytesize - 1, 0].max)
      @byte_pointer = Rvim::DisplayMotion.snap_back_to_char_boundary(target, @byte_pointer)
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

    INCLUSIVE_MOTION_CHARS = %w[$ e E f F t T %].freeze

    private def inclusive_motion_key?(key)
      INCLUSIVE_MOTION_CHARS.include?(key.char)
    end

    LINEWISE_MOTION_CHARS = %w[j k G H M L { } ( )].freeze
    LINEWISE_CTRL_BYTES = [0x04, 0x15].freeze # Ctrl-D, Ctrl-U

    private def linewise_motion?(key)
      ch = key.char
      return false if ch.nil?

      str = ch.is_a?(Integer) ? ch.chr : ch.to_s
      return true if LINEWISE_MOTION_CHARS.include?(str)
      return true if str.bytesize == 1 && LINEWISE_CTRL_BYTES.include?(str.bytes.first)

      # gg, gj, gk, ]] / [[ all dispatch through prefixes; we infer
      # linewise post-dispatch by comparing line indices.
      false
    end

    # Returns one of :handled (op applied or canceled, do nothing more),
    # :handed_off (text-object path will finish), :dispatch_motion (caller
    # in update should call super, then apply_op_to_range).
    private def preprocess_pending_op_key(key)
      ch = key.char
      ch_str = ch.is_a?(Integer) ? ch.chr : ch.to_s

      if ch_str == "\e"
        @rvim_pending_op = nil
        return :handled
      end

      if pending_op_doubled_key?(ch_str)
        op = @rvim_pending_op
        count = @rvim_pending_op_count
        @rvim_pending_op = nil
        pre_buffer = @buffer_of_lines.map(&:dup)
        apply_op_linewise(op, @line_index, @line_index + count - 1)
        push_undo_redo(true) if pre_buffer != @buffer_of_lines
        sync_current_buffer_lines
        return :handled
      end

      if ch_str == 'a' || ch_str == 'i'
        @vi_waiting_operator = case @rvim_pending_op
                               when :delete then :vi_delete_meta_confirm
                               when :change then :vi_change_meta_confirm
                               when :yank then :vi_yank_confirm
                               end
        @rvim_text_object_pending = ch_str == 'a' ? :around : :inner
        @rvim_pending_op = nil
        return :handed_off
      end

      # Count accumulator (d3w, c2j). Don't consume the pending op; let
      # Reline's argument-digit machinery accumulate via super.
      if ch_str =~ /\A[1-9]\z/ || (ch_str == '0' && @vi_arg && @vi_arg > 0)
        return :digit_count
      end

      :dispatch_motion
    end

    # Dispatch a motion key directly via its bound method symbol so we
    # can capture byte_pointer without Reline's vi-command tail clamp
    # rolling it back when the motion lands at EOL. Counts come from
    # @vi_arg or our pending-op count.
    private def dispatch_motion_for_op(key)
      sym = key.method_symbol || synthesize_key(key.char.is_a?(Integer) ? key.char.chr : key.char.to_s).method_symbol
      return unless sym

      count = @vi_arg && @vi_arg > 0 ? @vi_arg : @rvim_pending_op_count
      @vi_arg = nil
      args_method = method(sym)
      if args_method.arity == 1 || args_method.parameters.none? { |p| p[0] == :key }
        send(sym, key)
      else
        send(sym, key, arg: count)
      end
    rescue ArgumentError
      send(sym, key) # fallback for methods that take only key
    end

    private def pending_op_doubled_key?(ch_str)
      case @rvim_pending_op
      when :delete then ch_str == 'd'
      when :change then ch_str == 'c'
      when :yank then ch_str == 'y'
      else false
      end
    end

    # If the motion only changed line index (or the motion was hinted as
    # linewise), treat the op linewise. Charwise otherwise.
    private def lines_only_motion?(pre, post, hint_linewise)
      return true if hint_linewise
      pre[0] != post[0] && pre[1].zero? && post[1].zero?
    end

    private def apply_op_to_range(op, pre, post, kind:, inclusive: false)
      if pre == post && kind == :char
        # No motion happened (e.g. `dl` at end of line) — nothing to do.
        return
      end

      forward = (pre <=> post) <= 0
      start_pos, end_pos = forward ? [pre, post] : [post, pre]

      if kind == :line
        apply_op_linewise(op, start_pos[0], end_pos[0])
        return
      end

      # Charwise: forward motions are exclusive of the endpoint unless the
      # motion key was inclusive (e/E/$/f/t).
      if forward && !inclusive
        end_pos = predecessor_position(end_pos)
      end
      return if end_pos.nil? || (start_pos <=> end_pos) > 0

      sel = Rvim::Selection.from(:char, start_pos, end_pos, @buffer_of_lines)
      return unless sel

      run_operator_on_selection(op, sel)
    end

    private def apply_op_linewise(op, start_line, end_line)
      start_line = [start_line, 0].max
      end_line = [end_line, @buffer_of_lines.size - 1].min
      return if start_line > end_line

      sel = Rvim::Selection.from(:line, [start_line, 0], [end_line, 0], @buffer_of_lines)
      run_operator_on_selection(op, sel)
    end

    private def run_operator_on_selection(op, sel)
      case op
      when :delete
        Rvim::Operations.delete(self, sel)
        @modified = true
      when :change
        Rvim::Operations.change(self, sel)
        @modified = true
      when :yank
        Rvim::Operations.yank(self, sel)
      end
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

      target = Rvim::Search.next_match(@search_matches, @line_index, @byte_pointer, direction, wrapscan: @settings.get(:wrapscan))
      return unless target

      line, byte_start, byte_end = target

      if operator_pending?
        sel = Rvim::Selection.from(:char, [line, byte_start], [line, byte_end], @buffer_of_lines)
        before = @buffer_of_lines.map(&:dup)
        apply_pending_operator_to_range(sel)
        @modified = true if @buffer_of_lines != before
        @vi_waiting_operator = nil
        @vi_waiting_operator_arg = nil
        return
      end

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

      ensure_utf8(content.to_s).split("\n", -1).each_with_index do |line, i|
        @buffer_of_lines.insert(@line_index + 1 + i, String.new(line, encoding: encoding))
      end
      @line_index += 1
      @byte_pointer = 0
    end

    private def paste_lines_before(content)
      return unless content

      ensure_utf8(content.to_s).split("\n", -1).each_with_index do |line, i|
        @buffer_of_lines.insert(@line_index + i, String.new(line, encoding: encoding))
      end
      @byte_pointer = 0
    end

    private def paste_char_after(content)
      return unless content

      lines = ensure_utf8(content.to_s).split("\n", -1)
      current = @buffer_of_lines[@line_index] || (+'')
      # `p` pastes after the cursor — for multibyte cursors that means past
      # the whole codepoint, not just the next byte.
      insert_at = if current.bytesize.zero?
                    0
                  else
                    @byte_pointer + mbchar_size_forward(current, @byte_pointer)
                  end
      insert_at = [insert_at, current.bytesize].min

      head = current.byteslice(0, insert_at) || +''
      tail = current.byteslice(insert_at, current.bytesize - insert_at) || +''

      if lines.size == 1
        pasted = lines.first
        merged = head + pasted + tail
        @buffer_of_lines[@line_index] = String.new(merged, encoding: encoding)
        @byte_pointer = insert_at + pasted.bytesize - last_mbchar_size(pasted)
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
        @byte_pointer = [lines.last.bytesize - last_mbchar_size(lines.last), 0].max
      end
    end

    # Bytes consumed by the final character of `text`. For "あ" returns 3,
    # for "abc" returns 1, for "" returns 1 (cursor lands at 0).
    private def last_mbchar_size(text)
      return 1 if text.nil? || text.empty?

      size = Reline::Unicode.get_prev_mbchar_size(text, text.bytesize)
      size.positive? ? size : 1
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
        ch = key_for_proc.is_a?(Integer) ? key_for_proc.chr : key_for_proc.to_s
        case ch
        when 'Z'
          save if @filepath
          @quit = true
        when 'Q'
          # Quit without saving — same as :q!
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

    def self.init_lua_path
      base = ENV['XDG_CONFIG_HOME']
      base = File.expand_path('~/.config') if base.nil? || base.empty?
      File.join(base, 'rvim', 'init.lua')
    end

    def self.user_config_dir
      base = ENV['XDG_CONFIG_HOME']
      base = File.expand_path('~/.config') if base.nil? || base.empty?
      File.join(base, 'rvim')
    end

    # NeoVim auto-prepends $XDG_CONFIG_HOME/nvim and its after/ to runtimepath
    # so plugins authored as `~/.config/nvim/lua/<mod>.lua` are reachable via
    # require('<mod>'). Mirror that for rvim.
    def self.ensure_user_runtimepath(editor)
      cfg = user_config_dir
      after = File.join(cfg, 'after')
      rtp = editor.settings.get(:runtimepath).to_s.split(',')
      changed = false
      unless rtp.include?(cfg)
        rtp.unshift(cfg)
        changed = true
      end
      unless rtp.include?(after)
        rtp.push(after)
        changed = true
      end
      editor.settings.set(:runtimepath, rtp.join(',')) if changed
    end

    def self.start(*filepaths, norc: false)
      editor = new(Reline.core.config)
      filepaths = filepaths.flatten.compact
      editor.set_arg_list(filepaths)
      # Source the user's config BEFORE opening files, matching vim/nvim:
      # settings, autocmds, and feature flags (e.g. :lsp_enabled) need to
      # be in effect by the time BufRead fires for the first buffer.
      ensure_user_runtimepath(editor) unless norc
      unless norc
        [File.expand_path(RVIMRC_PATH), init_vim_path, init_lua_path].each do |rc|
          editor.source(rc) if File.exist?(rc)
        end
      end
      if filepaths.empty?
        # vim's [No Name] buffer: create an empty unnamed buffer and swap to it
        # so the screen has a current window/buffer to render into.
        editor.open(nil)
      else
        filepaths.each { |path| editor.open(path) }
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
            # Drain any pending LSP messages (diagnostics, hover responses,
            # etc.) so they're visible before the next render. Cheap when
            # no clients are running.
            if editor.settings.get(:lsp_enabled)
              editor.lsp.pump
              # Detect buffer edits and send textDocument/didChange so the
              # server analyzes the current text, not whatever it saw at
              # didOpen. Debounced internally.
              editor.lsp.note_change(editor.current_buffer)
              # Pull-mode diagnostics: ruby-lsp 0.26+ doesn't push, so we
              # refresh on a 500ms cadence so signs/underlines appear without
              # the user invoking :LspDiagnostics manually.
              editor.lsp.maybe_pull_diagnostics(editor.current_buffer)
              # Inlay hints are also pull-mode in LSP 3.17. Refresh on
              # a 1s cadence so labels stay current as the buffer changes.
              editor.lsp.maybe_pull_inlay_hints(editor.current_buffer)
            end
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
