# frozen_string_literal: true

module Rvim
  module SystemClipboard
    module_function

    def available?
      detect_tool != nil
    end

    def read
      raw = case detect_tool
            when :pbpaste then `pbpaste`
            when :xclip   then `xclip -selection clipboard -o 2>/dev/null`
            else ''
            end
      # Backticks return a string in Encoding.default_external; force-label as
      # UTF-8 and scrub any invalid byte sequences so downstream String#split
      # / regex calls don't raise on (e.g.) a mid-paste binary blob.
      raw = raw.dup.force_encoding(Encoding::UTF_8)
      raw.valid_encoding? ? raw : raw.scrub('?')
    end

    def write(text)
      tool = detect_tool
      return false unless tool

      cmd = case tool
            when :pbpaste then 'pbcopy'
            when :xclip   then 'xclip -selection clipboard -i'
            end
      IO.popen(cmd, 'w') { |io| io.write(text) }
      $?.success?
    end

    def detect_tool
      return @tool if defined?(@tool)

      @tool = if RUBY_PLATFORM =~ /darwin/ && which('pbpaste')
                :pbpaste
              elsif which('xclip')
                :xclip
              end
    end

    def which(cmd)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { |d| File.executable?(File.join(d, cmd)) }
    end
  end
end
