# frozen_string_literal: true

module Rvim
  module Syntax
    COLORS = {
      red:     "\e[31m",
      green:   "\e[32m",
      yellow:  "\e[33m",
      blue:    "\e[34m",
      magenta: "\e[35m",
      cyan:    "\e[36m",
      white:   "\e[37m",
      default: "\e[39m",
    }.freeze
    RESET = "\e[39m"

    @tokens = {}

    def self.register(lang, tokens)
      @tokens[lang] = tokens
    end

    def self.tokens_for(lang)
      @tokens[lang]
    end

    # Returns Array of [byte_start, byte_end, color_symbol].
    # byte_end is inclusive (matches our existing highlight conventions).
    def self.highlight(line, lang)
      table = @tokens[lang]
      return [] unless table

      segments = []
      table.each do |tok|
        offset = 0
        pattern = tok[:pattern]
        while (m = pattern.match(line, offset))
          b = m.pre_match.bytesize
          e = b + m[0].bytesize
          break if e == b # zero-width safety

          segments << [b, e - 1, tok[:color]]
          offset = m.end(0)
        end
      end
      coalesce(segments)
    end

    # Drop overlapping segments, keeping the earliest-starting one.
    # Tokens registered first dominate later ones at the same starting byte
    # because Ruby's stable sort preserves insertion order on tie.
    def self.coalesce(segments)
      sorted = segments.sort_by { |s, _e, _c| s }
      kept = []
      last_end = -1
      sorted.each do |s, e, c|
        next if s <= last_end

        kept << [s, e, c]
        last_end = e
      end
      kept
    end

    def self.detect_language(filepath)
      return nil unless filepath

      case File.extname(filepath)
      when '.rb', '.gemspec', '.rake' then :ruby
      when '.md', '.markdown' then :markdown
      when '.json' then :json
      end
    end
  end
end
