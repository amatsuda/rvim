# frozen_string_literal: true

require_relative '../syntax'

Rvim::Syntax.register(:markdown, [
  # Code spans first so backticks dominate over emphasis markers.
  { pattern: /`[^`]+`/,             color: :green },
  # Headings: 1-6 # marks at start of line through to EOL.
  { pattern: /^\#{1,6}\s.*$/,       color: :magenta },
  # Bold ** ** before italic so it wins on overlap.
  { pattern: /\*\*[^*\n]+\*\*/,     color: :magenta },
  # Italic.
  { pattern: /\*[^*\n]+\*/,         color: :yellow },
  # Links: [text](url)
  { pattern: /\[[^\]]*\]\([^)]*\)/, color: :cyan },
  # Bullet markers.
  { pattern: /^\s*[-*+]\s/,         color: :yellow },
  # Horizontal rule.
  { pattern: /^[-=*]{3,}\s*$/,      color: :yellow },
])
