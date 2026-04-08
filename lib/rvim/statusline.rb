# frozen_string_literal: true

module Rvim
  module Statusline
    # Format a vim-style statusline string. Supported placeholders (subset):
    #   %f  filename (display_name)
    #   %F  full path (filepath or '[No Name]')
    #   %m  modified flag ('[+]' or '')
    #   %r  readonly flag ('[RO]' or '') — always '' in v1
    #   %h  help-buffer flag ('[Help]' or '') — always '' in v1
    #   %y  filetype in brackets, e.g. '[ruby]'
    #   %l  cursor line (1-based)
    #   %L  total lines
    #   %c  cursor column (1-based byte)
    #   %p  percentage through file
    #   %n  buffer number
    #   %=  alignment marker (left of %= is left-aligned, right is right-aligned)
    #   %%  literal %
    def self.format(spec, editor, win, is_current:)
      buffer = win.buffer
      cursor_line = is_current ? editor.line_index : buffer.line_index
      cursor_byte = is_current ? editor.byte_pointer : buffer.byte_pointer
      total = (is_current ? editor.buffer_of_lines : buffer.lines).size
      modified = (is_current ? editor.modified : buffer.modified) ? '[+]' : ''
      filepath = buffer.filepath
      filetype = filepath ? (Rvim::Syntax.detect_language(filepath)&.to_s || '') : ''

      out = +''
      i = 0
      str = spec.to_s
      while i < str.length
        c = str[i]
        if c == '%' && i + 1 < str.length
          spec_char = str[i + 1]
          out << expand_placeholder(spec_char, {
            f: buffer.display_name,
            F: filepath || '[No Name]',
            m: modified,
            r: '',
            h: '',
            y: filetype.empty? ? '' : "[#{filetype}]",
            l: (cursor_line + 1).to_s,
            L: total.to_s,
            c: (cursor_byte + 1).to_s,
            p: total.zero? ? '0' : ((cursor_line + 1) * 100 / total).to_s,
            n: buffer.id.to_s,
            '%': '%',
            '=': "\x00ALIGN_RIGHT\x00",
          })
          i += 2
        else
          out << c
          i += 1
        end
      end
      out
    end

    def self.expand_placeholder(spec_char, table)
      key = spec_char == '%' ? :% : (spec_char == '=' ? :'=' : spec_char.to_sym)
      table.fetch(key, "%#{spec_char}")
    end

    # Apply the alignment marker to fit a width: left of marker stays left,
    # right of marker is right-aligned with padding between.
    def self.align_to_width(formatted, width)
      sentinel = "\x00ALIGN_RIGHT\x00"
      return formatted unless formatted.include?(sentinel)

      left, right = formatted.split(sentinel, 2)
      left ||= ''
      right ||= ''
      pad = width - left.length - right.length
      pad = 0 if pad.negative?
      "#{left}#{' ' * pad}#{right}"
    end
  end
end
