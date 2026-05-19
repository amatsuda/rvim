# frozen_string_literal: true

require 'json'

module Rvim
  module Lua
    # vim.json.encode / vim.json.decode — bridges to Ruby's JSON stdlib.
    # lazy.nvim parses its lock file with vim.json.decode; many LSP
    # config plugins encode/decode session state through here too.
    module Json
      module_function

      def install(state, _editor, _runtime)
        state.eval('vim.json = vim.json or {}')

        state.function 'vim.json.decode' do |s|
          ::JSON.parse(s.to_s)
        rescue ::JSON::ParserError
          # NeoVim raises here too; we surface nil so plugins can guard.
          nil
        end

        state.function 'vim.json.encode' do |v|
          ::JSON.generate(to_ruby(v))
        end
      end

      # Rufus::Lua::Table comes back as a Hash-like; convert numeric-keyed
      # tables to arrays so JSON output looks right (no { "1": ... }).
      def to_ruby(v)
        return v unless v.respond_to?(:to_h)

        h = v.to_h
        if h.empty?
          # An empty Lua table is ambiguous (array vs object). NeoVim
          # encodes it as object `{}`; we match that.
          {}
        elsif h.keys.all? { |k| k.is_a?(Numeric) && k.to_f == k.to_i }
          (1..h.size).map { |i| to_ruby(h[i] || h[i.to_f]) }
        else
          h.each_with_object({}) { |(k, val), acc| acc[k.to_s] = to_ruby(val) }
        end
      end
    end
  end
end
