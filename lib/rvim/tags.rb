# frozen_string_literal: true

module Rvim
  module Tags
    Entry = Struct.new(:name, :file, :excmd, keyword_init: true)

    class << self
      def load(paths)
        @tags = []
        @loaded_paths = []
        Array(paths).each do |path|
          next unless File.exist?(path)

          @loaded_paths << path
          base_dir = File.dirname(File.expand_path(path))
          File.foreach(path) do |raw|
            next if raw.start_with?('!')

            line = raw.chomp
            parts = line.split("\t", 3)
            next if parts.size < 3

            name, file, rest = parts
            excmd = if (idx = rest.index(%(;")))
                      rest[0...idx]
                    else
                      rest
                    end
            full_file = File.expand_path(file, base_dir)
            @tags << Entry.new(name: name, file: full_file, excmd: excmd)
          end
        end
        @tags
      end

      def find(name)
        all.select { |t| t.name == name }
      end

      def all
        @tags ||= []
      end

      def loaded_paths
        @loaded_paths ||= []
      end

      def reset!
        @tags = []
        @loaded_paths = []
      end

      # Given an excmd string and a buffer, return [line_index, byte_pointer]
      # or nil if the command can't be resolved.
      def locate(excmd, lines)
        return nil if excmd.nil? || lines.nil?

        s = excmd.to_s.strip
        if s.match?(/\A\d+\z/)
          return [s.to_i - 1, 0]
        end

        m = /\A\/(.*)\/\z/.match(s) || /\A\?(.*)\?\z/.match(s)
        return nil unless m

        pattern = m[1]
        pattern = pattern.sub(/\A\^/, '').sub(/\$\z/, '')
        pattern = pattern.gsub(/\\([\/^$])/) { Regexp.last_match(1) }
        lines.each_with_index do |line, i|
          return [i, 0] if line.to_s.include?(pattern)
        end
        nil
      end
    end
  end
end
