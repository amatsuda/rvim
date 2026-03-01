# frozen_string_literal: true

require_relative 'lib/rvim/version'

Gem::Specification.new do |spec|
  spec.name = 'rvim'
  spec.version = Rvim::VERSION
  spec.authors = ['Akira Matsuda']
  spec.email = ['ronnie@dio.jp']

  spec.summary = 'Pure Ruby Vim editor'
  spec.description = 'A NeoVim-compatible text editor written in pure Ruby on top of Reline.'
  spec.homepage = 'https://github.com/amatsuda/rvim'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.metadata['source_code_uri'] = spec.homepage

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[Gemfile .gitignore test/ .github/ docs/])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'reline'
end
