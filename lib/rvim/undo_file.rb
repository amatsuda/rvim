# frozen_string_literal: true

require 'fileutils'

module Rvim
  module UndoFile
    VERSION = 1

    def self.cache_dir
      base = ENV['XDG_CACHE_HOME']
      base = File.expand_path('~/.cache') if base.nil? || base.empty?
      File.join(base, 'rvim', 'undo')
    end

    def self.path_for(filepath)
      encoded = File.expand_path(filepath.to_s).gsub(File::SEPARATOR, '%')
      File.join(cache_dir, encoded)
    end

    def self.write(filepath, history, index)
      target = path_for(filepath)
      FileUtils.mkdir_p(File.dirname(target))
      payload = { version: VERSION, history: history, index: index }
      File.binwrite(target, Marshal.dump(payload))
      target
    rescue => _e
      nil
    end

    def self.read(filepath)
      target = path_for(filepath)
      return nil unless File.exist?(target)

      data = Marshal.load(File.binread(target))
      return nil unless data.is_a?(Hash) && data[:version] == VERSION

      [data[:history], data[:index]]
    rescue => _e
      nil
    end
  end
end
