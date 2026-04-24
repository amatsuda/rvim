# frozen_string_literal: true

require_relative '../syntax'

Rvim::Syntax.register(:javascript, [
  # Comments first.
  { pattern: %r{//[^\n]*}, color: :Comment },
  { pattern: %r{/\*(?:[^*]|\*(?!/))*\*/}, color: :Comment },
  # Strings: double, single, backtick template.
  { pattern: /"(?:\\.|[^"\\])*"/, color: :String },
  { pattern: /'(?:\\.|[^'\\])*'/, color: :String },
  { pattern: /`(?:\\.|[^`\\])*`/, color: :String },
  # Keywords.
  { pattern: /\b(?:var|let|const|function|return|if|else|while|do|for|in|of|switch|case|default|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|void|this|class|extends|super|import|export|from|as|async|await|yield|null|undefined|true|false|static|get|set)\b/, color: :Keyword },
  # Numbers.
  { pattern: /\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b/, color: :Number },
  # Regex literals (best-effort: /pat/flags after = , ( [ , ! & | ; : ? \n).
  { pattern: %r{(?<=[=,(\[!&|;:?])\s*/(?:\\.|[^/\\\n])+/[gimsuy]*}, color: :String },
  # Constants (UPPER_SNAKE).
  { pattern: /\b[A-Z][A-Z_0-9]+\b/, color: :Constant },
])
