# frozen_string_literal: true

module Rvim
  module Errorformat
    # Compile a single vim-style format spec into a regex with named captures.
    # Supported placeholders (subset):
    #   %f  filename → \S+
    #   %l  line number → \d+
    #   %c  column → \d+
    #   %m  message → .*
    #   %%  literal %
    def self.compile(spec)
      re = +'\A'
      i = 0
      str = spec.to_s
      while i < str.length
        if str[i] == '%' && i + 1 < str.length
          case str[i + 1]
          when 'f' then re << '(?<f>\S+)'
          when 'l' then re << '(?<l>\d+)'
          when 'c' then re << '(?<c>\d+)'
          when 'm' then re << '(?<m>.*)'
          when '%' then re << '%'
          else
            re << Regexp.escape(str[i, 2])
          end
          i += 2
        else
          re << Regexp.escape(str[i])
          i += 1
        end
      end
      re << '\z'
      Regexp.new(re)
    end

    # Parse `output` against a comma-separated format spec; returns an Array of
    # Quickfix::Entry. Lines that don't match any format are skipped.
    def self.parse(output, formats_spec)
      formats = formats_spec.to_s.split(',').map(&:strip).reject(&:empty?).map { |f| compile(f) }
      entries = []
      output.to_s.each_line do |line|
        line = line.chomp
        next if line.empty?

        formats.each do |re|
          if (m = re.match(line))
            entries << Rvim::Quickfix::Entry.new(
              file: m[:f],
              line: m.named_captures.fetch('l', '0').to_i,
              col: m.named_captures.fetch('c', '0').to_i,
              text: m.named_captures.fetch('m', line),
            )
            break
          end
        end
      end
      entries
    end
  end
end
