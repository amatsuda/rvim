# frozen_string_literal: true

module Rvim
  class Autocommands
    Entry = Struct.new(:event, :pattern, :command, :group, keyword_init: true)

    MAX_FIRE_DEPTH = 10

    def initialize
      @entries = []
      @current_group = nil
      @fire_depth = 0
    end

    attr_accessor :current_group

    def add(events, patterns, command)
      Array(events).each do |event|
        Array(patterns).each do |pattern|
          @entries << Entry.new(
            event: normalize_event(event),
            pattern: pattern.to_s,
            command: command.to_s,
            group: @current_group,
          )
        end
      end
    end

    def remove(event: nil, pattern: nil, group: :__any__)
      ev = event && normalize_event(event)
      grp = (group == :__any__) ? @current_group : group
      @entries.reject! do |e|
        (ev.nil? || e.event == ev) &&
          (pattern.nil? || e.pattern == pattern) &&
          (grp == :__any__ || e.group == grp)
      end
    end

    def clear_group(group)
      @entries.reject! { |e| e.group == group }
    end

    def clear_all
      @entries.clear
    end

    def fire(event, value, editor)
      ev = normalize_event(event)
      return if @fire_depth >= MAX_FIRE_DEPTH

      @fire_depth += 1
      begin
        # Snapshot to be safe against autocmds modifying the table.
        @entries.dup.each do |entry|
          next unless entry.event == ev
          next unless pattern_matches?(entry.pattern, value)

          parsed = Rvim::Command.parse(entry.command)
          Rvim::Command.execute(editor, parsed) if parsed
        end
      ensure
        @fire_depth -= 1
      end
    end

    def each(&block)
      @entries.each(&block)
    end

    def empty?
      @entries.empty?
    end

    def size
      @entries.size
    end

    private def normalize_event(name)
      name.to_s.downcase.to_sym
    end

    private def pattern_matches?(pattern, value)
      regex = self.class.pattern_to_regex(pattern)
      regex.match?(value.to_s)
    end

    def self.pattern_to_regex(pat)
      out = +'\A'
      i = 0
      while i < pat.length
        c = pat[i]
        case c
        when '*' then out << '.*'
        when '?' then out << '.'
        when '{'
          close = pat.index('}', i)
          if close
            alts = pat[(i + 1)...close].split(',').map { |a| Regexp.escape(a) }
            out << "(?:#{alts.join('|')})"
            i = close
          else
            out << Regexp.escape(c)
          end
        when '.', '+', '(', ')', '^', '$', '|', '\\', '[', ']'
          out << Regexp.escape(c)
        else
          out << c
        end
        i += 1
      end
      out << '\z'
      Regexp.new(out)
    end
  end
end
