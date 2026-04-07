# frozen_string_literal: true

module Rvim
  module Digraphs
    DEFAULT_TABLE = {
      # Ligatures
      'oe' => 'œ', 'OE' => 'Œ',
      'ae' => 'æ', 'AE' => 'Æ',
      'ss' => 'ß',
      # Punctuation / dashes / quotes
      '!I' => '¡', '?I' => '¿',
      '<<' => '«', '>>' => '»',
      '--' => '–', '-N' => '–', '-M' => '—',
      "'6" => '‘', "'9" => '’',
      '"6' => '“', '"9' => '”',
      '..' => '…',
      # Currency
      'Eu' => '€', 'Pd' => '£', 'Ye' => '¥', 'cu' => '¤',
      # Symbols
      'co' => '©', 'Tm' => '™', 'Rg' => '®', 'SS' => '§', 'No' => '№',
      'pa' => '¶', '/-' => '†', '/=' => '‡',
      # Math
      '+-' => '±', '-:' => '÷', '*X' => '×', 'no' => '¬',
      '<=' => '≤', '>=' => '≥', '!=' => '≠', '~=' => '≈',
      '~~' => '≃', '%0' => '‰',
      'In' => '∫', 'Sm' => '∑', 'sR' => '√',
      '00' => '∞', 'mu' => 'µ', 'DG' => '°',
      # Arrows
      '->' => '→', '<-' => '←', 'UP' => '↑', 'DA' => '↓',
      '=>' => '⇒',
      # Greek (lowercase)
      'a*' => 'α', 'b*' => 'β', 'g*' => 'γ', 'd*' => 'δ',
      'e*' => 'ε', 'l*' => 'λ', 'p*' => 'π', 'r*' => 'ρ',
      's*' => 'σ', 't*' => 'τ', 'w*' => 'ω', 'm*' => 'μ',
      # Accented Latin (acute)
      "'a" => 'á', "'A" => 'Á',
      "'e" => 'é', "'E" => 'É',
      "'i" => 'í', "'I" => 'Í',
      "'o" => 'ó', "'O" => 'Ó',
      "'u" => 'ú', "'U" => 'Ú',
      # Grave
      '`a' => 'à', '`A' => 'À',
      '`e' => 'è', '`E' => 'È',
      '`i' => 'ì', '`I' => 'Ì',
      '`o' => 'ò', '`O' => 'Ò',
      '`u' => 'ù', '`U' => 'Ù',
      # Umlaut / diaeresis
      '"a' => 'ä', '"A' => 'Ä',
      '"e' => 'ë', '"E' => 'Ë',
      '"i' => 'ï', '"I' => 'Ï',
      '"o' => 'ö', '"O' => 'Ö',
      '"u' => 'ü', '"U' => 'Ü',
      # Tilde
      '~a' => 'ã', '~A' => 'Ã',
      '~n' => 'ñ', '~N' => 'Ñ',
      '~o' => 'õ', '~O' => 'Õ',
      # Ring above
      'aA' => 'å', 'AA' => 'Å',
      # Cedilla
      ',c' => 'ç', ',C' => 'Ç',
      # Smileys / misc
      '<3' => '♥', ':)' => '☺', ':(' => '☹',
      'CL' => '♣', 'DI' => '♦', 'HE' => '♥', 'SP' => '♠',
    }.freeze

    class << self
      def user_table
        @user_table ||= {}
      end

      def lookup(pair)
        return nil unless pair.is_a?(String) && pair.length == 2

        user_table[pair] || DEFAULT_TABLE[pair]
      end

      def define(pair, value)
        text = value.is_a?(Integer) ? [value].pack('U') : value.to_s
        user_table[pair.to_s] = text
      end

      def each
        DEFAULT_TABLE.merge(user_table).each { |k, v| yield k, v }
      end

      def size
        DEFAULT_TABLE.size + user_table.size
      end

      def reset!
        @user_table = {}
      end
    end
  end
end
