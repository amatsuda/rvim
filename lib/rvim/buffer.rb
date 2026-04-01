# frozen_string_literal: true

module Rvim
  class Buffer
    attr_accessor :id, :filepath, :lines, :modified
    attr_accessor :marks, :line_index, :byte_pointer
    attr_accessor :undo_redo_history, :undo_redo_index, :last_visual
    attr_accessor :local_settings, :folds

    def initialize(id, filepath = nil, encoding: Encoding::UTF_8)
      @id = id
      @filepath = filepath
      @lines = if filepath && File.exist?(filepath)
                 File.readlines(filepath, chomp: true).map { |l| String.new(l, encoding: encoding) }
               else
                 [String.new('', encoding: encoding)]
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
    end

    def display_name
      @filepath || '[No Name]'
    end
  end
end
