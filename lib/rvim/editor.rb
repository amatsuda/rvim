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

    def self.start(filepath = nil)
      # Wired in Stage 4
      editor = new(Reline.core.config)
      editor.open(filepath) if filepath
      puts "rvim #{Rvim::VERSION}: opened #{editor.filepath || '(empty)'}, " \
           "#{editor.buffer_of_lines.size} line(s)"
    end
  end
end
