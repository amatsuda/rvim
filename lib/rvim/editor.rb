# frozen_string_literal: true

require 'reline'

module Rvim
  class Editor < Reline::LineEditor
    attr_reader :filepath
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
      install_key_bindings
    end

    private def install_key_bindings
      @config.add_default_key_binding_by_keymap(:vi_command, [?g.ord], :rvim_g_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?o.ord], :rvim_open_below)
      @config.add_default_key_binding_by_keymap(:vi_command, [?O.ord], :rvim_open_above)
      @config.add_default_key_binding_by_keymap(:vi_command, [?Z.ord], :rvim_z_prefix)
      @config.add_default_key_binding_by_keymap(:vi_command, [?:.ord], :rvim_enter_command_mode)
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
      else
        @status_message = nil
        before = @buffer_of_lines.map(&:dup)
        super
        @modified = true if before != @buffer_of_lines
      end
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
