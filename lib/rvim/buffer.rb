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

    def initialize(id, filepath = nil, encoding: Encoding::UTF_8)
      @id = id
      @filepath = filepath
      @fileformat = 'unix'
      @fileencoding = encoding.to_s.downcase
      @mtime = nil
      if filepath && File.exist?(filepath)
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
      @undo_redo_history = [[[String.new('', encoding: encoding)], 0, 0]]
      @undo_redo_index = 0
      @last_visual = nil
      @local_settings = {}
      @folds = Rvim::Folds.new
      @diff_active = false
      @diff_status = nil
      @vars = {}
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
