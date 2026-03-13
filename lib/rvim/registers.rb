# frozen_string_literal: true

module Rvim
  RegisterEntry = Struct.new(:text, :kind)

  class Registers
    UNNAMED = '"'

    def initialize
      @table = {}
    end

    def write(name, text, kind)
      effective = name.to_s.downcase
      append = name.to_s != effective

      entry = if append && @table.key?(effective)
                merge_append(@table[effective], text, kind)
              else
                RegisterEntry.new(text, kind)
              end
      @table[effective] = entry
      @table[UNNAMED] = entry.dup unless effective == UNNAMED
    end

    def read(name)
      @table[name.to_s.downcase]
    end

    def write_yank_history(text, kind)
      @table['0'] = RegisterEntry.new(text, kind)
    end

    def write_delete_history(text, kind)
      8.downto(1) do |i|
        if @table.key?(i.to_s)
          @table[(i + 1).to_s] = @table[i.to_s]
        end
      end
      @table['1'] = RegisterEntry.new(text, kind)
    end

    def all
      @table.dup
    end

    private def merge_append(existing, text, kind)
      a, b = existing.text, text
      if existing.kind == :line || kind == :line
        joined = a.to_s
        joined += "\n" unless joined.end_with?("\n")
        joined += b.to_s
        RegisterEntry.new(joined, :line)
      else
        RegisterEntry.new(a.to_s + b.to_s, kind)
      end
    end
  end
end
