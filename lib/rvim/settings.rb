# frozen_string_literal: true

module Rvim
  class Settings
    DEFAULTS = {
      hlsearch: true,
      ignorecase: false,
      shiftwidth: 2,
      number: false,
      relativenumber: false,
      smartcase: false,
      syntax: :auto,
      wrap: true,
      tabstop: 8,
      scrolloff: 0,
      cursorline: false,
      ruler: true,
      list: false,
      foldenable: true,
      foldmethod: 'manual',
      foldlevel: 99,
      modeline: true,
      modelines: 5,
      undofile: false,
      wildmenu: true,
      spell: false,
      spelllang: 'en',
      tags: './tags,tags',
      expandtab: false,
      listchars: 'tab:> ,trail:·',
      colorcolumn: '',
      cursorcolumn: false,
      fileformat: 'unix',
      statusline: '',
      fileencoding: 'utf-8',
      virtualedit: '',
      mouse: '',
      sidescrolloff: 0,
    }.freeze

    ALIASES = {
      'hls' => :hlsearch,
      'ic' => :ignorecase,
      'nu' => :number,
      'rnu' => :relativenumber,
      'scs' => :smartcase,
      'sw' => :shiftwidth,
      'syn' => :syntax,
      'ts' => :tabstop,
      'so' => :scrolloff,
      'cul' => :cursorline,
      'ru' => :ruler,
      'fen' => :foldenable,
      'fdm' => :foldmethod,
      'fdl' => :foldlevel,
      'ml' => :modeline,
      'mls' => :modelines,
      'udf' => :undofile,
      'wmnu' => :wildmenu,
      'et' => :expandtab,
      'lcs' => :listchars,
      'cc' => :colorcolumn,
      'cuc' => :cursorcolumn,
      'ff' => :fileformat,
      'stl' => :statusline,
      'fenc' => :fileencoding,
      've' => :virtualedit,
      'siso' => :sidescrolloff,
    }.freeze

    KNOWN = (DEFAULTS.keys + ALIASES.values).uniq.freeze

    def initialize
      @options = DEFAULTS.dup
      @editor = nil
    end

    attr_accessor :editor

    def get(name, buffer: :current)
      key = normalize(name)
      buf = buffer == :current ? @editor&.current_buffer : buffer
      if buf && buf.respond_to?(:local_settings) && buf.local_settings.key?(key)
        buf.local_settings[key]
      else
        @options[key]
      end
    end

    def set(name, value, buffer: nil)
      key = normalize(name)
      if buffer
        buffer.local_settings[key] = value
      else
        @options[key] = value
      end
      key
    end

    def known?(name)
      KNOWN.include?(normalize(name))
    end

    def normalize(name)
      sym = name.to_s
      ALIASES[sym] || sym.to_sym
    end
  end
end
