# frozen_string_literal: true

module Rvim
  class Settings
    DEFAULTS = {
      hlsearch: true,
      shiftwidth: 2,
      number: false,
      relativenumber: false,
      syntax: :auto,
    }.freeze

    ALIASES = {
      'hls' => :hlsearch,
      'nu' => :number,
      'rnu' => :relativenumber,
      'sw' => :shiftwidth,
      'syn' => :syntax,
    }.freeze

    KNOWN = (DEFAULTS.keys + ALIASES.values).uniq.freeze

    def initialize
      @options = DEFAULTS.dup
    end

    def get(name)
      @options[normalize(name)]
    end

    def set(name, value)
      key = normalize(name)
      @options[key] = value
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
