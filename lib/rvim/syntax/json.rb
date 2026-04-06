# frozen_string_literal: true

require_relative '../syntax'

Rvim::Syntax.register(:json, [
  # Strings cover both keys and values; JSON has no other string contexts.
  { pattern: /"(?:\\.|[^"\\])*"/,                    color: :String },
  # Numbers including negative, decimal, exponent.
  { pattern: /-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/, color: :Number },
  # Literals.
  { pattern: /\b(?:true|false|null)\b/,              color: :Constant },
])
