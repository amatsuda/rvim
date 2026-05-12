# frozen_string_literal: true

module Rvim
  module CmdlineCompletion
    Context = Struct.new(:kind, :partial, :prefix, keyword_init: true)

    FILE_VERBS = %w[e edit r read source so cd chdir sp split vsp vsplit tabe tabedit tabnew w write].freeze
    SET_VERBS = %w[set se setlocal setl].freeze

    # Inspect the cmdline buffer and decide what to complete.
    # Returns a Context with kind ∈ {:command, :filename, :setting, :none},
    # the `partial` text to expand, and the unchanged `prefix` to keep.
    def self.analyze(buffer)
      str = buffer.to_s

      # Empty or just leading whitespace → completing a command name from start
      return Context.new(kind: :command, partial: '', prefix: '') if str.strip.empty?

      # If buffer has no whitespace yet, the user is typing the verb.
      unless str.include?(' ')
        return Context.new(kind: :command, partial: str, prefix: '')
      end

      verb, rest = str.split(/\s+/, 2)
      verb_norm = verb.to_s.delete_suffix('!')

      if FILE_VERBS.include?(verb_norm)
        partial = rest.to_s.split(/\s+/).last.to_s
        prefix = str[0...str.length - partial.length]
        return Context.new(kind: :filename, partial: partial, prefix: prefix)
      end

      if SET_VERBS.include?(verb_norm)
        partial = rest.to_s.split(/\s+/).last.to_s
        # Strip the no- prefix so "noi<Tab>" still finds 'ignorecase'
        bare = partial.sub(/\Ano/, '')
        prefix_text = str[0...str.length - partial.length]
        return Context.new(kind: :setting, partial: bare, prefix: prefix_text + (partial.start_with?('no') ? 'no' : ''))
      end

      Context.new(kind: :none, partial: '', prefix: str)
    end

    # Fallback list used only when command.rb can't be scraped at load
    # time (e.g. unusual install layout). Real list comes from
    # `ex_commands` below.
    EX_COMMANDS_FALLBACK = %w[
      w write q quit wq x e edit r read b buffer ls
      bn bp bd sp vsp set source autocmd help
      tabnew tabe tabclose
    ].sort.uniq.freeze

    # Scrape the verbs from command.rb's main `case verb_str` block so
    # newly-added ex-commands (e.g. :LspRename, :LspCodeAction) appear
    # in tab completion automatically without anyone having to update
    # this file.
    def self.ex_commands
      @ex_commands ||= scrape_ex_commands.freeze
    end

    def self.scrape_ex_commands
      path = File.expand_path('command.rb', __dir__)
      return EX_COMMANDS_FALLBACK unless File.exist?(path)

      verbs = []
      in_case = false
      File.foreach(path) do |line|
        unless in_case
          in_case = true if line =~ /^\s*verb\s*=\s*case\s+verb_str\b/
          next
        end
        # The case block ends with `else nil` followed by `end`.
        break if line =~ /^\s*else\b/

        line.scan(/'([A-Za-z][A-Za-z_!]*)'/) { |m| verbs << m[0] }
      end
      # Case-insensitive sort so capitalized verbs (LspXxx) interleave
      # with lowercase common ones (a, abbreviate, …) instead of all
      # landing at the head of the alphabet via ASCII order.
      verbs.uniq.sort_by { |v| [v.downcase, v] }
    rescue StandardError
      EX_COMMANDS_FALLBACK
    end

    def self.candidates(context, editor)
      raw = case context.kind
            when :command
              ex_commands.select { |c| c.start_with?(context.partial) }
            when :filename
              glob = context.partial.empty? ? '*' : "#{context.partial}*"
              paths = Dir.glob(glob).map { |path| File.directory?(path) ? "#{path}/" : path }
              paths = filter_wildignore(paths, editor)
              paths.sort
            when :setting
              Rvim::Settings::DEFAULTS.keys.map(&:to_s).select { |k| k.start_with?(context.partial) }.sort
            else
              []
            end
      # Drop the bare partial so cycling moves to richer candidates.
      raw.reject { |c| c == context.partial }
    end

    def self.filter_wildignore(paths, editor)
      patterns = editor.settings.get(:wildignore).to_s.split(',').map(&:strip).reject(&:empty?)
      return paths if patterns.empty?

      paths.reject do |path|
        patterns.any? { |pat| File.fnmatch?(pat, path) || File.fnmatch?(pat, File.basename(path)) }
      end
    end
  end
end
