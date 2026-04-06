# frozen_string_literal: true

require_relative '../syntax'

Rvim::Syntax.register(:shell, [
  # Comments first to dominate everything else.
  { pattern: /\#[^\n]*/,                            color: :Comment },
  # Strings (double then single).
  { pattern: /"(?:\\.|[^"\\])*"/,                   color: :String },
  { pattern: /'[^']*'/,                             color: :String },
  # Variables: ${name}, $name, $1-$9, $!?@#*$
  { pattern: /\$\{[^}]+\}/,                         color: :Identifier },
  { pattern: /\$\w+|\$[!?@#*$]|\$\d/,               color: :Identifier },
  # Keywords.
  { pattern: /\b(?:if|then|elif|else|fi|for|while|until|do|done|in|case|esac|function|return|exit|local|export|readonly|set|unset|break|continue)\b/, color: :Keyword },
  # Numbers.
  { pattern: /\b\d+\b/,                             color: :Number },
])
