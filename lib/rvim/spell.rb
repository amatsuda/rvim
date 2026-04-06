# frozen_string_literal: true

require 'set'
require 'fileutils'

module Rvim
  module Spell
    DEFAULT_DICT_PATHS = [
      '/usr/share/dict/words',
      '/usr/share/dict/american-english',
      '/usr/share/dict/british-english',
    ].freeze

    class << self
      attr_writer :dict, :good_set, :bad_set

      def dict
        @dict ||= load_dictionary
      end

      def good_set
        @good_set ||= load_user_set('good.txt')
      end

      def bad_set
        @bad_set ||= load_user_set('bad.txt')
      end

      def load_dictionary(paths = DEFAULT_DICT_PATHS)
        paths.each do |p|
          next unless File.exist?(p)

          words = File.foreach(p).map { |l| l.chomp.downcase }
          return words.to_set
        end
        Set.new
      end

      def reset!
        @dict = nil
        @good_set = nil
        @bad_set = nil
      end

      def misspelled?(word)
        return false if word.nil? || word.empty?
        return false unless word.match?(/\A[A-Za-z]/)

        w = word.downcase
        return true if bad_set.include?(w)
        return false if good_set.include?(w)

        !dict.include?(w)
      end

      def add_good(word)
        good_set << word.downcase
        bad_set.delete(word.downcase)
        persist('good.txt', good_set)
      end

      def add_bad(word)
        bad_set << word.downcase
        good_set.delete(word.downcase)
        persist('bad.txt', bad_set)
      end

      def suggest(word, n: 5, max_dist: 3)
        w = word.downcase
        scored = []
        dict.each do |entry|
          delta = (entry.length - w.length).abs
          next if delta > max_dist

          d = distance(w, entry)
          scored << [d, entry] if d <= max_dist
        end
        scored.sort.first(n).map { |_, e| e }
      end

      def distance(a, b)
        m = a.length
        n = b.length
        return n if m.zero?
        return m if n.zero?

        prev = (0..n).to_a
        cur = Array.new(n + 1, 0)
        (1..m).each do |i|
          cur[0] = i
          (1..n).each do |j|
            cost = a[i - 1] == b[j - 1] ? 0 : 1
            cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].min
          end
          prev, cur = cur, prev
        end
        prev[n]
      end

      def cache_dir
        base = ENV['XDG_CACHE_HOME']
        base = File.expand_path('~/.cache') if base.nil? || base.empty?
        File.join(base, 'rvim', 'spell')
      end

      def load_user_set(filename)
        path = File.join(cache_dir, filename)
        return Set.new unless File.exist?(path)

        File.foreach(path).each_with_object(Set.new) { |l, s| s << l.chomp.downcase }
      rescue
        Set.new
      end

      def persist(filename, words)
        FileUtils.mkdir_p(cache_dir)
        File.write(File.join(cache_dir, filename), words.to_a.sort.join("\n"))
      rescue
        nil
      end
    end
  end
end
