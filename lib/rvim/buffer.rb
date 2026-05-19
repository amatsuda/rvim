# frozen_string_literal: true

module Rvim
  class Buffer
    attr_accessor :id, :filepath, :lines, :modified
    attr_accessor :marks, :line_index, :byte_pointer
    attr_accessor :undo_redo_history, :undo_redo_index, :last_visual
    attr_accessor :local_settings, :folds
    attr_accessor :diff_active, :diff_status
    attr_accessor :fileformat, :fileencoding, :mtime
    attr_accessor :vars
    # Scratch buffer (no file backing, buftype='nofile') and listed
    # flag — exposed by vim.api.nvim_create_buf(listed, scratch).
    # `bufhidden` controls cleanup-on-close behaviour (telescope sets
    # 'wipe' so its prompt/results/preview buffers vanish after the
    # picker closes).
    attr_accessor :scratch, :listed, :bufhidden, :buftype

    def initialize(id, filepath = nil, encoding: Encoding::UTF_8, scratch: false, listed: true)
      @id = id
      @filepath = filepath
      @fileformat = 'unix'
      @fileencoding = encoding.to_s.downcase
      @mtime = nil
      @scratch = scratch
      @listed = listed
      @bufhidden = scratch ? 'hide' : ''
      @buftype = scratch ? 'nofile' : ''
      if filepath && File.exist?(filepath) && !scratch
        raw = File.binread(filepath)
        @mtime = File.mtime(filepath)
        @fileformat = detect_fileformat(raw)
        decoded = decode_with_encoding(raw, encoding)
        @lines = split_with_format(decoded, @fileformat).map { |l| String.new(l, encoding: encoding) }
      else
        @lines = [String.new('', encoding: encoding)]
      end
      @lines = [String.new('', encoding: encoding)] if @lines.empty?
      @modified = false
      @marks = Rvim::Marks.new
      @line_index = 0
      @byte_pointer = 0
      # Seed the undo history with the file's actual loaded content so the
      # very first undo from a post-edit state restores the on-disk view,
      # not Reline's empty default.
      @undo_redo_history = [[@lines.map(&:dup), 0, 0]]
      @undo_redo_index = 0
      @last_visual = nil
      @local_settings = {}
      @folds = Rvim::Folds.new
      @diff_active = false
      @diff_status = nil
      @vars = {}
    end

    def scratch?
      @scratch == true
    end

    # Per-buffer keymap, instantiated lazily. Buffer-local mappings
    # (nvim_buf_set_keymap, vim.keymap.set({ buffer = N })) live
    # here and take precedence over the editor's global keymap when
    # this buffer is current.
    def keymap
      @keymap ||= Rvim::Keymap.new
    end

    def keymap?
      !@keymap.nil?
    end

    # Extmarks: namespaced annotations attached to byte ranges of
    # buffer lines. Stored as { ns_id => { mark_id => Hash } } where
    # each mark Hash has line, col, end_row, end_col, hl_group,
    # priority, plus any opts the caller passed. Mark ids are
    # monotonic per buffer.
    def extmarks
      @extmarks ||= Hash.new { |h, ns| h[ns] = {} }
    end

    def next_extmark_id!
      @next_extmark_id ||= 0
      @next_extmark_id += 1
    end

    # Buffer change listeners. nvim_buf_attach(bufnr, _,
    # { on_lines = fn }) registers fn here; Editor fires it whenever
    # `lines` mutates as part of the edit loop. Each listener is
    # `Proc(event, bufnr, changedtick, first_line, last_line,
    # new_last_line, byte_count)` — close enough to NeoVim's
    # signature that telescope-style "refilter on every keystroke"
    # plugins work.
    def attach_listener(callback)
      (@listeners ||= []) << callback
    end

    def detach_listener(callback)
      @listeners&.delete(callback)
    end

    def fire_lines_event(first_line, old_last_line, new_last_line, byte_count = 0)
      return if @listeners.nil? || @listeners.empty?

      tick = @undo_redo_index.to_i
      @listeners.each do |cb|
        cb.call('lines', @id, tick, first_line, old_last_line, new_last_line, byte_count)
      rescue StandardError
        # Listener errors must never take the editor down.
        nil
      end
    end

    def display_name
      @filepath || '[No Name]'
    end

    def file_changed_externally?
      return false unless @filepath && File.exist?(@filepath)
      return false if @mtime.nil?

      File.mtime(@filepath) > @mtime
    end

    def reload(encoding: Encoding::UTF_8)
      return unless @filepath && File.exist?(@filepath)

      raw = File.binread(@filepath)
      @mtime = File.mtime(@filepath)
      @fileformat = detect_fileformat(raw)
      decoded = decode_with_encoding(raw, encoding)
      @lines = split_with_format(decoded, @fileformat).map { |l| String.new(l, encoding: encoding) }
      @lines = [String.new('', encoding: encoding)] if @lines.empty?
      @line_index = @line_index.clamp(0, [@lines.size - 1, 0].max)
      target = @lines[@line_index] || ''
      @byte_pointer = @byte_pointer.clamp(0, [target.bytesize - 1, 0].max)
    end

    private def decode_with_encoding(raw, target_encoding)
      raw.force_encoding(target_encoding)
      raw.valid_encoding? ? raw : raw.force_encoding(Encoding::ASCII_8BIT)
    rescue ArgumentError
      raw.force_encoding(Encoding::ASCII_8BIT)
    end

    private def detect_fileformat(raw)
      return 'unix' if raw.empty?
      return 'dos' if raw.include?("\r\n")
      return 'mac' if raw.include?("\r")

      'unix'
    end

    private def split_with_format(raw, ff)
      sep = case ff
            when 'dos' then "\r\n"
            when 'mac' then "\r"
            else "\n"
            end
      lines = raw.split(sep, -1)
      lines.pop if lines.last == ''
      lines
    end
  end
end
