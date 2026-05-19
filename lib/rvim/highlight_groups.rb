# frozen_string_literal: true

module Rvim
  # Named highlight-group → SGR pair registry. Lua plugins reference
  # groups by string ("Search", "Visual", "TelescopeSelection", etc.);
  # rvim resolves the name to an open / close pair of ANSI escapes
  # that the renderer splices around extmark spans.
  #
  # Seeded with vim's standard groups so plugins that just say
  # `hl_group = 'Search'` work without extra setup. nvim_set_hl can
  # override or add groups at runtime.
  class HighlightGroups
    Pair = Struct.new(:open, :close)

    # SGR codes commonly enough that we factor them out.
    BOLD_ON, BOLD_OFF       = "\e[1m", "\e[22m"
    ITALIC_ON, ITALIC_OFF   = "\e[3m", "\e[23m"
    UNDERLINE_ON, UNDER_OFF = "\e[4m", "\e[24m"
    REVERSE_ON, REVERSE_OFF = "\e[7m", "\e[27m"
    FG_RESET, BG_RESET      = "\e[39m", "\e[49m"

    DEFAULTS = {
      'CursorLine'         => [+"\e[48;5;236m", +"\e[49m"],
      'Visual'             => [+"\e[7m",        +"\e[27m"],
      'Search'             => [+"\e[7m",        +"\e[27m"],
      'IncSearch'          => [+"\e[48;5;220;38;5;232m", +"\e[39;49m"],
      'CurSearch'          => [+"\e[48;5;220;38;5;232m", +"\e[39;49m"],
      'MatchParen'         => [+"\e[48;5;240m", +"\e[49m"],
      'TelescopeSelection' => [+"\e[48;5;240m", +"\e[49m"],
      'TelescopeMatching'  => [+"\e[1;38;5;220m", +"\e[22;39m"],
      'TelescopeBorder'    => [+"\e[38;5;245m", +"\e[39m"],
      'Comment'            => [+"\e[38;5;245m", +"\e[39m"],
      'String'             => [+"\e[38;5;150m", +"\e[39m"],
      'Number'             => [+"\e[38;5;209m", +"\e[39m"],
      'Keyword'            => [+"\e[38;5;197m", +"\e[39m"],
      'Function'           => [+"\e[38;5;81m",  +"\e[39m"],
      'Type'               => [+"\e[38;5;178m", +"\e[39m"],
      'ErrorMsg'           => [+"\e[1;38;5;196m", +"\e[22;39m"],
      'WarningMsg'         => [+"\e[1;38;5;214m", +"\e[22;39m"],
    }.freeze

    def initialize
      @groups = DEFAULTS.transform_values { |o, c| Pair.new(+o, +c) }
    end

    # Register / override a group from a NeoVim-style spec hash:
    #   { fg = 'NvimLightYellow', bg = 'NvimDarkGray',
    #     bold = true, italic = false, underline = false, reverse = false }
    # fg / bg accept 256-color integers or named-color strings via a
    # small built-in map (Red, Green, Blue, Cyan, Magenta, Yellow,
    # White, Black, Gray, plus 'Nvim*' aliases). Unknown names fall
    # back to default fg/bg.
    def define(name, spec)
      open = +''
      close = +''
      spec = stringify(spec)
      apply_color(spec['fg'], open, close, fg: true)
      apply_color(spec['bg'], open, close, fg: false)
      apply_attr(BOLD_ON, BOLD_OFF, open, close) if spec['bold']
      apply_attr(ITALIC_ON, ITALIC_OFF, open, close) if spec['italic']
      apply_attr(UNDERLINE_ON, UNDER_OFF, open, close) if spec['underline']
      apply_attr(REVERSE_ON, REVERSE_OFF, open, close) if spec['reverse']
      @groups[name.to_s] = Pair.new(open, close)
    end

    def lookup(name)
      @groups[name.to_s]
    end

    def defined?(name)
      @groups.key?(name.to_s)
    end

    def names
      @groups.keys
    end

    NAMED_COLORS = {
      'black' => 0, 'red' => 1, 'green' => 2, 'yellow' => 3,
      'blue' => 4, 'magenta' => 5, 'cyan' => 6, 'white' => 7,
      'gray' => 8, 'grey' => 8,
      'brightred' => 9, 'brightgreen' => 10, 'brightyellow' => 11,
      'brightblue' => 12, 'brightmagenta' => 13, 'brightcyan' => 14,
      'brightwhite' => 15,
      # Approximations for common Nvim* names.
      'nvimlightyellow' => 220, 'nvimdarkyellow' => 178,
      'nvimlightred' => 203, 'nvimdarkred' => 124,
      'nvimlightgreen' => 150, 'nvimdarkgreen' => 22,
      'nvimlightblue' => 81, 'nvimdarkblue' => 24,
      'nvimlightgray' => 245, 'nvimdarkgray' => 237,
    }.freeze

    private def apply_color(val, open, close, fg:)
      return if val.nil? || val == 'NONE' || val == false || val == ''

      idx = resolve_color(val)
      return if idx.nil?

      if idx < 16
        open  << "\e[#{(fg ? 30 : 40) + idx}m"
        close << (fg ? FG_RESET : BG_RESET)
      else
        open  << "\e[#{fg ? 38 : 48};5;#{idx}m"
        close << (fg ? FG_RESET : BG_RESET)
      end
    end

    private def resolve_color(val)
      return val.to_i if val.is_a?(Numeric)
      return val.to_i if val.respond_to?(:match?) && val.match?(/\A\d+\z/)

      s = val.to_s.downcase.gsub(/[^a-z]/, '')
      NAMED_COLORS[s]
    end

    private def apply_attr(on, off, open, close)
      open  << on
      close << off
    end

    private def stringify(h)
      case h
      when Hash then h.transform_keys(&:to_s)
      else (h.respond_to?(:to_h) ? h.to_h.transform_keys(&:to_s) : {})
      end
    end
  end
end
