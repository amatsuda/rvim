# frozen_string_literal: true

module Rvim
  module Completion
    # Collect unique \w+ tokens from all buffer lines, drop the bare base,
    # filter to those starting with base, sort alphabetically. base = '' returns
    # every distinct word.
    def self.candidates(buffer_lines, base, infercase: false)
      seen = {}
      buffer_lines.each do |line|
        line.to_s.scan(/\w+/) { |w| seen[w] = true }
      end
      base = base.to_s
      seen.delete(base)
      words = seen.keys

      unless base.empty?
        if infercase
          base_lower = base.downcase
          words = words.select { |w| w.downcase.start_with?(base_lower) }
          words = words.map { |w| match_case_to_base(w, base) }
        else
          words = words.select { |w| w.start_with?(base) }
        end
      end

      words.sort
    end

    def self.match_case_to_base(candidate, base)
      return candidate if base.empty?

      n = [base.length, candidate.length].min
      adjusted = candidate.dup
      n.times do |i|
        bc = base[i]
        cc = candidate[i]
        next if bc.nil? || cc.nil?

        adjusted[i] = if bc =~ /[A-Z]/
                       cc.upcase
                     elsif bc =~ /[a-z]/
                       cc.downcase
                     else
                       cc
                     end
      end
      adjusted
    end

    # Walk left from byte_pointer over word characters; return the byte slice.
    def self.base_at(line, byte_pointer)
      return '' if line.nil? || line.empty?

      i = byte_pointer
      while i > 0 && line.byteslice(i - 1, 1) =~ /\w/
        i -= 1
      end
      line.byteslice(i, byte_pointer - i) || ''
    end

    def self.base_start(line, byte_pointer)
      return byte_pointer if line.nil? || line.empty?

      i = byte_pointer
      i -= 1 while i > 0 && line.byteslice(i - 1, 1) =~ /\w/
      i
    end

    # Filename completion: base is the run of non-whitespace characters to the
    # left of the cursor (so paths like 'lib/foo' work).
    def self.path_base_at(line, byte_pointer)
      return '' if line.nil? || line.empty?

      i = byte_pointer
      while i > 0 && line.byteslice(i - 1, 1) !~ /\s/
        i -= 1
      end
      line.byteslice(i, byte_pointer - i) || ''
    end

    def self.path_base_start(line, byte_pointer)
      return byte_pointer if line.nil? || line.empty?

      i = byte_pointer
      i -= 1 while i > 0 && line.byteslice(i - 1, 1) !~ /\s/
      i
    end

    def self.candidates_files(base)
      glob = base.to_s.empty? ? '*' : "#{base}*"
      paths = Dir.glob(glob)
      paths.map { |p| File.directory?(p) ? "#{p}/" : p }.sort
    end

    def self.candidates_dictionary(base)
      return [] unless defined?(Rvim::Spell)

      dict = Rvim::Spell.dict
      return [] if dict.empty? || base.to_s.empty?

      dict.select { |w| w.start_with?(base.to_s.downcase) }.sort.first(50)
    end

    def self.candidates_lines(buffer_lines, base_line)
      base = base_line.to_s
      filtered = buffer_lines.uniq.reject { |l| l.to_s.empty? }
      filtered = filtered.select { |l| l.to_s.start_with?(base) } unless base.empty?
      filtered.reject { |l| l.to_s == base }.sort
    end
  end
end
