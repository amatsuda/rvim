# frozen_string_literal: true

module Rvim
  module Highlights
    Attr = Struct.new(:fg, :bg, :bold, :italic, :underline, :reverse, keyword_init: true)

    COLOR_CODES = {
      'black' => 30, 'red' => 31, 'green' => 32, 'yellow' => 33,
      'blue' => 34, 'magenta' => 35, 'cyan' => 36, 'white' => 37,
      'darkblue' => 34, 'darkred' => 31, 'darkgreen' => 32, 'darkyellow' => 33,
      'darkmagenta' => 35, 'darkcyan' => 36, 'darkgray' => 90, 'darkgrey' => 90,
      'gray' => 37, 'grey' => 37, 'lightgray' => 37, 'lightgrey' => 37,
      'default' => 39, 'none' => 39,
    }.freeze

    DEFAULT_THEME = {
      'Normal'       => Attr.new,
      'Comment'      => Attr.new(fg: 'cyan'),
      'String'       => Attr.new(fg: 'green'),
      'Number'       => Attr.new(fg: 'red'),
      'Keyword'      => Attr.new(fg: 'magenta'),
      'Constant'     => Attr.new(fg: 'blue'),
      'Identifier'   => Attr.new(fg: 'yellow'),
      'Statement'    => Attr.new(fg: 'magenta'),
      'Type'         => Attr.new(fg: 'blue'),
      'Special'      => Attr.new(fg: 'yellow'),
      'PreProc'      => Attr.new(fg: 'magenta'),
      'Symbol'       => Attr.new(fg: 'yellow'),
      'Title'        => Attr.new(fg: 'magenta', bold: true),
      'Bold'         => Attr.new(bold: true),
      'Italic'       => Attr.new(italic: true),
      'Link'         => Attr.new(fg: 'cyan', underline: true),
      'LineNr'       => Attr.new(fg: 'darkgray'),
      'CursorLineNr' => Attr.new(fg: 'yellow', bold: true),
      'StatusLine'   => Attr.new(reverse: true),
      'Folded'       => Attr.new(fg: 'darkgray'),
      'DiffAdd'      => Attr.new(bg: 'green'),
      'DiffDelete'   => Attr.new(bg: 'red'),
      'DiffChange'   => Attr.new(bg: 'yellow'),
      'DiffText'     => Attr.new(bg: 'red', bold: true),
      'Search'       => Attr.new(reverse: true),
      'IncSearch'    => Attr.new(reverse: true),
      'Visual'       => Attr.new(reverse: true),
      'Error'        => Attr.new(fg: 'red', bold: true),
      'Todo'         => Attr.new(fg: 'yellow', bold: true),
      'NonText'      => Attr.new(fg: 'darkgray'),
      'SpellBad'     => Attr.new(fg: 'red'),
      'ColorColumn'  => Attr.new(bg: 'darkred'),
      'CursorColumn' => Attr.new(bg: 'darkgray'),
    }.freeze

    class << self
      def groups
        @groups ||= DEFAULT_THEME.transform_values(&:dup)
      end

      def set(name, fg: nil, bg: nil, bold: nil, italic: nil, underline: nil, reverse: nil)
        cur = groups[name] || Attr.new
        groups[name] = Attr.new(
          fg: fg.nil? ? cur.fg : fg,
          bg: bg.nil? ? cur.bg : bg,
          bold: bold.nil? ? cur.bold : bold,
          italic: italic.nil? ? cur.italic : italic,
          underline: underline.nil? ? cur.underline : underline,
          reverse: reverse.nil? ? cur.reverse : reverse,
        )
      end

      def get(name)
        groups[name.to_s]
      end

      def clear(name)
        groups[name.to_s] = Attr.new
      end

      def reset_to_defaults!
        @groups = DEFAULT_THEME.transform_values(&:dup)
      end

      def ansi_prefix(name)
        attr = get(name) or return ''

        parts = +''
        parts << "\e[1m" if attr.bold
        parts << "\e[3m" if attr.italic
        parts << "\e[4m" if attr.underline
        parts << "\e[7m" if attr.reverse
        if attr.fg
          code = COLOR_CODES[attr.fg.to_s.downcase] || 39
          parts << "\e[#{code}m"
        end
        if attr.bg
          fg_code = COLOR_CODES[attr.bg.to_s.downcase] || 49
          # Background = fg_code + 10 for the basic 8/16 set
          bg_code = fg_code >= 90 ? fg_code + 10 : fg_code + 10
          parts << "\e[#{bg_code}m"
        end
        parts
      end

      def ansi_suffix(name)
        attr = get(name) or return ''

        parts = +''
        parts << "\e[39m" if attr.fg
        parts << "\e[49m" if attr.bg
        parts << "\e[22m" if attr.bold
        parts << "\e[23m" if attr.italic
        parts << "\e[24m" if attr.underline
        parts << "\e[27m" if attr.reverse
        parts
      end

      def wrap(name, text)
        "#{ansi_prefix(name)}#{text}#{ansi_suffix(name)}"
      end
    end
  end
end
