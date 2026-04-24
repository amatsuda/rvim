# frozen_string_literal: true

require_relative '../syntax'

Rvim::Syntax.register(:yaml, [
  # Comments.
  { pattern: /\#[^\n]*/, color: :Comment },
  # Document markers.
  { pattern: /^(?:---|\.\.\.)\s*$/, color: :PreProc },
  # Anchors and aliases (&foo / *foo).
  { pattern: /[&*][A-Za-z_][A-Za-z_0-9]*/, color: :Identifier },
  # Tags (!!str, !MyTag).
  { pattern: /!!?[A-Za-z_][A-Za-z_0-9]*/, color: :Type },
  # Keys followed by colon.
  { pattern: /^\s*[A-Za-z_][A-Za-z_0-9.\-]*(?=:)/, color: :Identifier },
  # Strings.
  { pattern: /"(?:\\.|[^"\\])*"/, color: :String },
  { pattern: /'(?:''|[^'])*'/, color: :String },
  # Booleans / null.
  { pattern: /\b(?:true|false|null|yes|no|on|off|True|False|Null|None)\b/, color: :Keyword },
  # Numbers.
  { pattern: /\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b/, color: :Number },
])
