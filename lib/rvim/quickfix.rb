# frozen_string_literal: true

module Rvim
  class Quickfix
    Entry = Struct.new(:file, :line, :col, :text, keyword_init: true)

    def initialize
      @entries = []
      @index = 0
    end

    def set(entries)
      @entries = entries.dup
      @index = 0
    end

    def add(entry)
      @entries << entry
    end

    def clear
      @entries = []
      @index = 0
    end

    def size
      @entries.size
    end

    def empty?
      @entries.empty?
    end

    def current
      @entries[@index]
    end

    attr_reader :index, :entries

    def at(idx)
      return nil if idx < 0 || idx >= @entries.size

      @index = idx
      @entries[idx]
    end

    def advance(direction)
      return nil if @entries.empty?

      @index = (@index + direction).clamp(0, @entries.size - 1)
      @entries[@index]
    end

    def each(&block)
      @entries.each(&block)
    end
  end
end
