# frozen_string_literal: true

require_relative '../syntax'

Rvim::Syntax.register(:shell, [
  # Comments first to dominate everything else.
  { pattern: /\#[^\n]*/,                            color: :cyan },
  # Strings (double then single).
  { pattern: /"(?:\\.|[^"\\])*"/,                   color: :green },
  { pattern: /'[^']*'/,                             color: :green },
  # Variables: ${name}, $name, $1-$9, $!?@#*$
  { pattern: /\$\{[^}]+\}/,                         color: :yellow },
  { pattern: /\$\w+|\$[!?@#*$]|\$\d/,               color: :yellow },
  # Keywords.
  { pattern: /\b(?:if|then|elif|else|fi|for|while|until|do|done|in|case|esac|function|return|exit|local|export|readonly|set|unset|break|continue)\b/, color: :magenta },
  # Numbers.
  { pattern: /\b\d+\b/,                             color: :red },
])
