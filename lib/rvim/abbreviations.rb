# frozen_string_literal: true

module Rvim
  class Abbreviations
    Entry = Struct.new(:rhs, :recursive, keyword_init: true)

    MODES = %i[insert cmdline].freeze

    def initialize
      @table = {} # mode => { lhs => Entry }
      MODES.each { |m| @table[m] = {} }
    end

    def add(modes, lhs, rhs, recursive: true)
      Array(modes).each { |m| @table[m][lhs] = Entry.new(rhs: rhs, recursive: recursive) }
    end

    def remove(modes, lhs)
      Array(modes).each { |m| @table[m].delete(lhs) }
    end

    def clear(modes)
      Array(modes).each { |m| @table[m] = {} }
    end

    def lookup(mode, lhs)
      @table[mode][lhs]
    end

    def each(mode)
      @table[mode].each { |lhs, entry| yield(lhs, entry) }
    end

    def empty?(mode)
      @table[mode].empty?
    end

    # Given a buffer line and a byte position right after a word-terminator
    # was typed, find the abbreviation lhs to expand (if any). Returns
    # [start_byte, end_byte, entry] for the lhs run, or nil.
    def detect(line, byte_pointer, mode)
      return nil if byte_pointer <= 0

      # The terminator was just inserted at byte_pointer-1; the word ends at
      # byte_pointer-1 (exclusive of the terminator). Walk back to find word
      # boundary.
      word_end = byte_pointer - 1
      return nil if word_end <= 0

      i = word_end - 1
      while i >= 0 && line.byteslice(i, 1) =~ /[A-Za-z0-9_]/
        i -= 1
      end
      word_start = i + 1
      return nil if word_start >= word_end

      lhs = line.byteslice(word_start, word_end - word_start)
      entry = lookup(mode, lhs)
      return nil unless entry

      [word_start, word_end, entry]
    end
  end
end
