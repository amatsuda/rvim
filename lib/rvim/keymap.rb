# frozen_string_literal: true

module Rvim
  class Keymap
    Mapping = Struct.new(:lhs, :rhs, :recursive, :silent, keyword_init: true)

    MODES = %i[normal visual insert op_pending cmdline].freeze

    MAP_MODES = %i[normal visual op_pending].freeze
    BANG_MODES = %i[insert cmdline].freeze

    def initialize
      @table = MODES.each_with_object({}) { |m, h| h[m] = {} }
    end

    def add(modes, lhs, rhs, recursive: true, silent: false)
      Array(modes).each do |mode|
        next unless @table[mode]

        @table[mode][lhs] = Mapping.new(lhs: lhs, rhs: rhs, recursive: recursive, silent: silent)
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

    def self.expand(str, leader: '\\')
      out = +''
      i = 0
      while i < str.length
        if str[i] == '<' && (close = str.index('>', i))
          tag = str[(i + 1)...close]
          out << expand_tag(tag, leader: leader)
          i = close + 1
        else
          out << str[i]
          i += 1
        end
      end
      out
    end

    def self.expand_tag(tag, leader: '\\')
      case tag.downcase
      when 'cr', 'enter', 'return' then "\r"
      when 'esc' then "\e"
      when 'tab' then "\t"
      when 'space' then ' '
      when 'bs' then "\x7f"
      when 'lt' then '<'
      when 'gt' then '>'
      when 'nl', 'lf' then "\n"
      when 'nul' then "\x00"
      when 'up' then "\e[A"
      when 'down' then "\e[B"
      when 'right' then "\e[C"
      when 'left' then "\e[D"
      when 'home' then "\e[H"
      when 'end' then "\e[F"
      when 'pageup' then "\e[5~"
      when 'pagedown' then "\e[6~"
      when 'insert' then "\e[2~"
      when 'delete', 'del' then "\e[3~"
      when 'leader' then leader
      when 'f1' then "\eOP"
      when 'f2' then "\eOQ"
      when 'f3' then "\eOR"
      when 'f4' then "\eOS"
      when 'f5' then "\e[15~"
      when 'f6' then "\e[17~"
      when 'f7' then "\e[18~"
      when 'f8' then "\e[19~"
      when 'f9' then "\e[20~"
      when 'f10' then "\e[21~"
      when 'f11' then "\e[23~"
      when 'f12' then "\e[24~"
      when /\Ac-(.)\z/i
        ch = Regexp.last_match(1)
        (ch.upcase.ord & 0x1f).chr
      when /\As-(.)\z/i
        Regexp.last_match(1).upcase
      else
        "<#{tag}>"
      end
    end

    REVERSE_TAGS = {
      "\r" => '<CR>',
      "\e" => '<Esc>',
      "\t" => '<Tab>',
      "\x7f" => '<BS>',
      "\n" => '<NL>',
      "\x00" => '<Nul>',
      "\e[A" => '<Up>',
      "\e[B" => '<Down>',
      "\e[C" => '<Right>',
      "\e[D" => '<Left>',
      "\e[H" => '<Home>',
      "\e[F" => '<End>',
      "\e[5~" => '<PageUp>',
      "\e[6~" => '<PageDown>',
      "\e[2~" => '<Insert>',
      "\e[3~" => '<Delete>',
    }.freeze

    REVERSE_KEYS_LONG_FIRST = REVERSE_TAGS.keys.sort_by { |k| -k.bytesize }.freeze

    def self.render(str)
      out = +''
      i = 0
      while i < str.bytesize
        matched = REVERSE_KEYS_LONG_FIRST.find { |k| str.byteslice(i, k.bytesize) == k }
        if matched
          out << REVERSE_TAGS[matched]
          i += matched.bytesize
        else
          ch = str.byteslice(i, 1)
          if ch && ch.bytes.first < 0x20
            out << format('<C-%s>', (ch.bytes.first | 0x40).chr)
          else
            out << ch.to_s
          end
          i += 1
        end
      end
      out
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
      cmap: %i[cmdline],
      cnoremap: %i[cmdline],
      unmap: MAP_MODES,
      nunmap: %i[normal],
      vunmap: %i[visual],
      iunmap: %i[insert],
      ounmap: %i[op_pending],
      cunmap: %i[cmdline],
      mapclear: MAP_MODES,
      nmapclear: %i[normal],
      vmapclear: %i[visual],
      imapclear: %i[insert],
      omapclear: %i[op_pending],
      cmapclear: %i[cmdline],
    }.freeze

    BANG_VERBS = %i[map noremap unmap mapclear].freeze

    def self.modes_for(verb, bang: false)
      return BANG_MODES if bang && BANG_VERBS.include?(verb)

      MODES_FOR_VERB[verb]
    end

    def self.noremap?(verb)
      %i[noremap nnoremap vnoremap inoremap onoremap cnoremap].include?(verb)
    end

    def self.unmap?(verb)
      %i[unmap nunmap vunmap iunmap ounmap cunmap].include?(verb)
    end

    def self.mapclear?(verb)
      %i[mapclear nmapclear vmapclear imapclear omapclear cmapclear].include?(verb)
    end
  end
end
