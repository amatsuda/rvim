# frozen_string_literal: true

require_relative '../syntax'

Rvim::Syntax.register(:python, [
  # Comments first.
  { pattern: /\#[^\n]*/, color: :Comment },
  # Triple-quoted strings, then double, then single.
  { pattern: /"""(?:\\.|[^\\])*?"""/, color: :String },
  { pattern: /'''(?:\\.|[^\\])*?'''/, color: :String },
  { pattern: /"(?:\\.|[^"\\])*"/, color: :String },
  { pattern: /'(?:\\.|[^'\\])*'/, color: :String },
  # Decorators.
  { pattern: /@[A-Za-z_][A-Za-z_0-9.]*/, color: :PreProc },
  # Keywords.
  { pattern: /\b(?:def|class|if|elif|else|while|for|in|return|yield|pass|break|continue|raise|try|except|finally|with|as|import|from|global|nonlocal|lambda|and|or|not|is|None|True|False|async|await|match|case)\b/, color: :Keyword },
  # Builtins.
  { pattern: /\b(?:print|len|range|str|int|float|bool|list|dict|set|tuple|type|isinstance|hasattr|getattr|setattr|self|cls)\b/, color: :Identifier },
  # Numbers.
  { pattern: /\b(?:0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?j?)\b/, color: :Number },
  # Constants (UPPERCASE identifiers).
  { pattern: /\b[A-Z][A-Z_0-9]+\b/, color: :Constant },
])
