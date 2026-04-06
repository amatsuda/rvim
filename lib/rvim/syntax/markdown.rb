# frozen_string_literal: true

require_relative '../syntax'

Rvim::Syntax.register(:markdown, [
  # Code spans first so backticks dominate over emphasis markers.
  { pattern: /`[^`]+`/,             color: :String },
  # Headings: 1-6 # marks at start of line through to EOL.
  { pattern: /^\#{1,6}\s.*$/,       color: :Title },
  # Bold ** ** before italic so it wins on overlap.
  { pattern: /\*\*[^*\n]+\*\*/,     color: :Bold },
  # Italic.
  { pattern: /\*[^*\n]+\*/,         color: :Italic },
  # Links: [text](url)
  { pattern: /\[[^\]]*\]\([^)]*\)/, color: :Link },
  # Bullet markers.
  { pattern: /^\s*[-*+]\s/,         color: :Special },
  # Horizontal rule.
  { pattern: /^[-=*]{3,}\s*$/,      color: :Special },
])
