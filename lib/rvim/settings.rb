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
