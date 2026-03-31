# frozen_string_literal: true

module Rvim
  class Keymap
    Mapping = Struct.new(:lhs, :rhs, :recursive, keyword_init: true)

    MODES = %i[normal visual insert op_pending].freeze

    MAP_MODES = %i[normal visual op_pending].freeze

    def initialize
      @table = MODES.each_with_object({}) { |m, h| h[m] = {} }
    end

    def add(modes, lhs, rhs, recursive: true)
      Array(modes).each do |mode|
        @table[mode][lhs] = Mapping.new(lhs: lhs, rhs: rhs, recursive: recursive)
      end
    end

    def remove(modes, lhs)
      Array(modes).each { |mode| @table[mode].delete(lhs) }
    end

    def clear(modes)
      Array(modes).each { |mode| @table[mode]&.clear }
    end

    def lookup(mode, pending)
      table = @table[mode] || {}
      exact = table[pending]
      return [:exact, exact] if exact
      return [:prefix, nil] if table.keys.any? { |lhs| lhs.start_with?(pending) && lhs != pending }

      [:none, nil]
    end

    def empty?(mode)
      (@table[mode] || {}).empty?
    end

    def each(mode)
      (@table[mode] || {}).each { |lhs, mapping| yield lhs, mapping }
    end

    def self.expand(str)
      out = +''
      i = 0
      while i < str.length
        if str[i] == '<' && (close = str.index('>', i))
          tag = str[(i + 1)...close]
          out << expand_tag(tag)
          i = close + 1
        else
          out << str[i]
          i += 1
        end
      end
      out
    end

    def self.expand_tag(tag)
      case tag.downcase
      when 'cr', 'enter', 'return' then "\r"
      when 'esc' then "\e"
      when 'tab' then "\t"
      when 'space' then ' '
      when 'bs' then "\x7f"
      when 'lt' then '<'
      when 'gt' then '>'
      when 'leader' then '\\'
      when /\Ac-(.)\z/i
        ch = Regexp.last_match(1)
        (ch.upcase.ord & 0x1f).chr
      when /\As-(.)\z/i
        Regexp.last_match(1).upcase
      else
        "<#{tag}>"
      end
    end

    MODES_FOR_VERB = {
      map: MAP_MODES,
      noremap: MAP_MODES,
      nmap: %i[normal],
      nnoremap: %i[normal],
      vmap: %i[visual],
      vnoremap: %i[visual],
      imap: %i[insert],
      inoremap: %i[insert],
      omap: %i[op_pending],
      onoremap: %i[op_pending],
      unmap: MAP_MODES,
      nunmap: %i[normal],
      vunmap: %i[visual],
      iunmap: %i[insert],
      ounmap: %i[op_pending],
      mapclear: MAP_MODES,
      nmapclear: %i[normal],
      vmapclear: %i[visual],
      imapclear: %i[insert],
      omapclear: %i[op_pending],
    }.freeze

    def self.modes_for(verb)
      MODES_FOR_VERB[verb]
    end

    def self.noremap?(verb)
      %i[noremap nnoremap vnoremap inoremap onoremap].include?(verb)
    end

    def self.unmap?(verb)
      %i[unmap nunmap vunmap iunmap ounmap].include?(verb)
    end

    def self.mapclear?(verb)
      %i[mapclear nmapclear vmapclear imapclear omapclear].include?(verb)
    end
  end
end
