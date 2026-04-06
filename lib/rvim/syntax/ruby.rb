# frozen_string_literal: true

require_relative '../syntax'

Rvim::Syntax.register(:ruby, [
  # Comments — must register first to dominate everything that follows on the line.
  { pattern: /#[^\n]*/, color: :Comment },

  # Strings — register before keywords so "def" inside a string isn't keyword-colored.
  { pattern: /"(?:\\.|[^"\\])*"/, color: :String },
  { pattern: /'(?:\\.|[^'\\])*'/, color: :String },
  { pattern: /`(?:\\.|[^`\\])*`/, color: :String },

  # Keywords.
  { pattern: /\b(?:def|end|if|elsif|else|unless|while|until|for|do|case|when|then|return|class|module|begin|rescue|ensure|raise|yield|next|break|redo|retry|in|self|nil|true|false|and|or|not|require|require_relative)\b/, color: :Keyword },

  # Symbols.
  { pattern: /:[A-Za-z_][A-Za-z_0-9]*[!?=]?/, color: :Symbol },

  # Numbers.
  { pattern: /\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b/, color: :Number },

  # Constants (CamelCase identifiers).
  { pattern: /\b[A-Z][A-Za-z_0-9]*/, color: :Constant },
])
