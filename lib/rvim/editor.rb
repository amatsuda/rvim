# frozen_string_literal: true

require 'reline'

module Rvim
  class Editor < Reline::LineEditor
    attr_reader :filepath, :visual_mode, :visual_anchor
    attr_accessor :modified, :command_mode, :command_buffer, :status_message

    def initialize(config)
      super
      @config.editing_mode = :vi_command
      multiline_on
      @filepath = nil
      @modified = false
      @quit = false
      @command_mode = false
      @command_buffer = +''
      @status_message = nil
      @visual_mode = nil
      @visual_anchor = nil
      @last_visual = nil
      install_key_bindings
    end

    private def install_key_bindings
      @config.add_default_key_binding_by_keymap(:vi_command, [?g.ord], :rvim_g_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?o.ord], :rvim_open_below)
      @config.add_default_key_binding_by_keymap(:vi_command, [?O.ord], :rvim_open_above)
      @config.add_default_key_binding_by_keymap(:vi_command, [?Z.ord], :rvim_z_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?:.ord], :rvim_enter_command_mode)
      @config.add_default_key_binding_by_keymap(:vi_command, [?u.ord], :undo)
      @config.add_default_key_binding_by_keymap(:vi_command, [0x12], :redo) # Ctrl-R
      @config.add_default_key_binding_by_keymap(:vi_command, [?d.ord], :rvim_d_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?p.ord], :rvim_paste_after)
      @config.add_default_key_binding_by_keymap(:vi_command, [?P.ord], :rvim_paste_before)
      @config.add_default_key_binding_by_keymap(:vi_command, [?v.ord], :rvim_visual_char)
      @config.add_default_key_binding_by_keymap(:vi_command, [?V.ord], :rvim_visual_line)
      @config.add_default_key_binding_by_keymap(:vi_command, [0x16], :rvim_visual_block) # Ctrl-V
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
      if @command_mode
        process_command_key(key)
      elsif @visual_mode
        return if intercept_visual_key(key)

        before = @buffer_of_lines.map(&:dup)
        super
        @modified = true if before != @buffer_of_lines
      else
        @status_message = nil
        before = @buffer_of_lines.map(&:dup)
        super
        @modified = true if before != @buffer_of_lines
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
      false
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

    private def process_command_key(key)
      ch = key.char
      if ch.nil?
        cancel_command
        return
      end
      case ch
      when "\r", "\n"
        execute_command
      when "\e"
        cancel_command
      when "\x7f", "\b" # backspace / DEL
        if @command_buffer.empty?
          cancel_command
        else
          @command_buffer.chop!
        end
      else
        @command_buffer << ch.to_s
      end
    end

    private def execute_command
      parsed = Rvim::Command.parse(@command_buffer)
      Rvim::Command.execute(self, parsed) if parsed
      @command_mode = false
      @command_buffer = +''
    end

    private def cancel_command
      @command_mode = false
      @command_buffer = +''
      @status_message = nil
    end

    private def rvim_enter_command_mode(key)
      @command_mode = true
      @command_buffer = +''
      @status_message = nil
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

    private def vi_to_history_line(key)
      @line_index = @buffer_of_lines.size - 1
      @byte_pointer = 0
    end

    private def rvim_g_prefix(key)
      @waiting_proc = lambda do |key_for_proc, _sym|
        @waiting_proc = nil
        if key_for_proc == 'g' || key_for_proc == 'g'.ord
          @line_index = 0
          @byte_pointer = 0
        end
      end
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

    private def rvim_d_prefix(key)
      @waiting_proc = lambda do |key_for_proc, _sym|
        @waiting_proc = nil
        if key_for_proc == 'd' || key_for_proc == 'd'.ord
          delete_current_line_linewise
        end
      end
    end

    private def delete_current_line_linewise
      return if @buffer_of_lines.empty?

      cut = @buffer_of_lines.delete_at(@line_index)
      @rvim_clipboard = cut
      @rvim_clipboard_linewise = true
      if @buffer_of_lines.empty?
        @buffer_of_lines = [String.new(encoding: encoding)]
        @line_index = 0
      elsif @line_index >= @buffer_of_lines.size
        @line_index = @buffer_of_lines.size - 1
      end
      @byte_pointer = 0
    end

    private def rvim_paste_after(key, arg: 1)
      if @rvim_clipboard_linewise && @rvim_clipboard
        @buffer_of_lines.insert(@line_index + 1, String.new(@rvim_clipboard, encoding: encoding))
        @line_index += 1
        @byte_pointer = 0
      else
        vi_paste_next(key, arg: arg)
      end
    end

    private def rvim_paste_before(key, arg: 1)
      if @rvim_clipboard_linewise && @rvim_clipboard
        @buffer_of_lines.insert(@line_index, String.new(@rvim_clipboard, encoding: encoding))
        @byte_pointer = 0
      else
        vi_paste_prev(key, arg: arg)
      end
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
