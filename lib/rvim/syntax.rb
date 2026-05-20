# frozen_string_literal: true

module Rvim
  module Syntax
    COLORS = {
      red:     "\e[31m",
      green:   "\e[32m",
      yellow:  "\e[33m",
      blue:    "\e[34m",
      magenta: "\e[35m",
      cyan:    "\e[36m",
      white:   "\e[37m",
      default: "\e[39m",
    }.freeze
    RESET = "\e[39m"

    @tokens = {}

    def self.register(lang, tokens)
      @tokens[lang] = tokens
    end

    def self.tokens_for(lang)
      @tokens[lang]
    end

    # Returns Array of [byte_start, byte_end, color_symbol].
    # byte_end is inclusive (matches our existing highlight conventions).
    # Filetypes that share a highlight table with a parent engine.
    # detect_language can return precise names (typescript / scss /
    # objc) for plugin/LSP routing; the painter falls back to the
    # parent for tokenization.
    LANG_ALIASES = {
      typescript: :javascript, tsx: :javascript, jsx: :javascript,
      scss: :css, sass: :css, less: :css,
      objc: :c, objcpp: :cpp,
      bash: :shell, zsh: :shell, sh: :shell,
      typescriptreact: :javascript, javascriptreact: :javascript,
    }.freeze

    def self.highlight(line, lang)
      table = @tokens[lang] || @tokens[LANG_ALIASES[lang]]
      return [] unless table

      segments = []
      table.each do |tok|
        offset = 0
        pattern = tok[:pattern]
        while (m = pattern.match(line, offset))
          b = m.pre_match.bytesize
          e = b + m[0].bytesize
          break if e == b # zero-width safety

          segments << [b, e - 1, tok[:color]]
          offset = m.end(0)
        end
      end
      coalesce(segments)
    end

    # Drop overlapping segments, keeping the earliest-starting one.
    # Tokens registered first dominate later ones at the same starting byte
    # because Ruby's stable sort preserves insertion order on tie.
    def self.coalesce(segments)
      sorted = segments.sort_by { |s, _e, _c| s }
      kept = []
      last_end = -1
      sorted.each do |s, e, c|
        next if s <= last_end

        kept << [s, e, c]
        last_end = e
      end
      kept
    end

    EXT_FILETYPES = {
      # Ruby family
      '.rb' => :ruby, '.gemspec' => :ruby, '.rake' => :ruby, '.ru' => :ruby,
      '.builder' => :ruby, '.podspec' => :ruby, '.rbs' => :rbs,
      # Markup
      '.md' => :markdown, '.markdown' => :markdown, '.mdown' => :markdown,
      '.html' => :html, '.htm' => :html, '.xhtml' => :html, '.xml' => :xml,
      '.svg' => :xml, '.css' => :css, '.scss' => :scss, '.sass' => :sass,
      '.less' => :less,
      # Data
      '.json' => :json, '.jsonl' => :json, '.json5' => :json,
      '.yml' => :yaml, '.yaml' => :yaml,
      '.toml' => :toml,
      '.csv' => :csv, '.tsv' => :tsv,
      # Shell / config
      '.sh' => :shell, '.bash' => :shell, '.zsh' => :shell, '.ksh' => :shell,
      '.fish' => :fish,
      '.conf' => :conf, '.cfg' => :conf, '.ini' => :dosini,
      # Python
      '.py' => :python, '.pyw' => :python, '.pyi' => :python,
      # JS / TS
      '.js' => :javascript, '.mjs' => :javascript, '.cjs' => :javascript,
      '.jsx' => :javascript, '.ts' => :typescript, '.tsx' => :typescript,
      # C family
      '.c' => :c, '.h' => :c,
      '.cc' => :cpp, '.cpp' => :cpp, '.cxx' => :cpp, '.hpp' => :cpp, '.hh' => :cpp,
      '.m' => :objc, '.mm' => :objcpp,
      # Other languages
      '.go' => :go, '.rs' => :rust, '.swift' => :swift, '.kt' => :kotlin,
      '.kts' => :kotlin, '.scala' => :scala, '.java' => :java,
      '.clj' => :clojure, '.cljs' => :clojurescript,
      '.lua' => :lua, '.vim' => :vim, '.vimrc' => :vim,
      '.ex' => :elixir, '.exs' => :elixir, '.erl' => :erlang, '.hrl' => :erlang,
      '.hs' => :haskell, '.lhs' => :haskell,
      '.ml' => :ocaml, '.mli' => :ocaml,
      '.r' => :r, '.R' => :r, '.Rmd' => :rmd,
      '.pl' => :perl, '.pm' => :perl,
      '.php' => :php,
      '.sql' => :sql,
      '.tex' => :tex, '.bib' => :bib,
      '.dart' => :dart,
      '.zig' => :zig,
      '.nim' => :nim, '.nims' => :nim,
      # Build / project
      '.mk' => :make, '.makefile' => :make,
      '.gradle' => :groovy, '.groovy' => :groovy,
    }.freeze

    BASENAME_FILETYPES = {
      'Gemfile' => :ruby, 'Gemfile.lock' => :ruby, 'Rakefile' => :ruby,
      'Capfile' => :ruby, 'Vagrantfile' => :ruby, 'Berksfile' => :ruby,
      'Brewfile' => :ruby, 'Guardfile' => :ruby, 'Procfile' => :ruby,
      'config.ru' => :ruby,
      'Dockerfile' => :dockerfile, 'Containerfile' => :dockerfile,
      'Makefile' => :make, 'makefile' => :make, 'GNUmakefile' => :make,
      '.gitconfig' => :gitconfig, '.gitignore' => :gitignore,
      '.gitattributes' => :gitattributes, 'COMMIT_EDITMSG' => :gitcommit,
      'MERGE_MSG' => :gitcommit, 'TAG_EDITMSG' => :gitcommit,
      '.bashrc' => :shell, '.zshrc' => :shell, '.profile' => :shell,
      '.bash_profile' => :shell, '.bash_aliases' => :shell,
      '.vimrc' => :vim, '.gvimrc' => :vim,
      'CMakeLists.txt' => :cmake,
    }.freeze

    SHEBANG_FILETYPES = {
      %r{\bruby\b}    => :ruby,
      %r{\bpython\d*\b} => :python,
      %r{\bnode\b}    => :javascript,
      %r{\bdeno\b}    => :javascript,
      %r{\bbun\b}     => :javascript,
      %r{\bperl\b}    => :perl,
      %r{\bphp\b}     => :php,
      %r{/bin/(?:ba|z|k|d|)sh\b} => :shell,
      %r{\bbash\b}    => :shell,
      %r{\bzsh\b}     => :shell,
      %r{\bfish\b}    => :fish,
      %r{\blua\b}     => :lua,
    }.freeze

    def self.detect_language(filepath)
      return nil unless filepath

      basename = File.basename(filepath)
      if (ft = BASENAME_FILETYPES[basename])
        return ft
      end

      ext = File.extname(filepath)
      if (ft = EXT_FILETYPES[ext])
        return ft
      end

      # Shebang sniff — only for files that exist and start with #!
      detect_by_shebang(filepath)
    end

    def self.detect_by_shebang(filepath)
      return nil unless File.file?(filepath)

      first = File.open(filepath, 'r') { |f| f.gets(128) } rescue nil
      return nil if first.nil? || !first.start_with?('#!')

      SHEBANG_FILETYPES.each do |re, ft|
        return ft if first.match?(re)
      end
      nil
    end
  end
end
