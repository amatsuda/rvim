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

    EX_COMMANDS = %w[
      w write q quit qa qall wq x cq edit e read r
      bn bnext bp bprev bdelete bd b buffer ls buffers
      sp split vsp vsplit set setlocal source so
      autocmd au augroup aug history his marks jumps registers reg
      tabnew tabe tabedit tabnext tabn tabprev tabp tabclose tabc tabonly tabo tabmove tabm
      resize res vertical
      let fold fo nohlsearch noh retab cd chdir pwd
      vimgrep vim cnext cn cprev cp cc clist cl copen cope cclose cclo
      delete d yank y put p move m copy co t join j sort
      map nmap vmap imap omap cmap noremap nnoremap vnoremap inoremap onoremap cnoremap
      unmap nunmap vunmap iunmap ounmap cunmap mapclear nmapclear vmapclear imapclear omapclear cmapclear
    ].sort.uniq.freeze

    def self.candidates(context, editor)
      raw = case context.kind
            when :command
              EX_COMMANDS.select { |c| c.start_with?(context.partial) }
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
