# frozen_string_literal: true

module Rvim
  module FileType
    @hooks = Hash.new { |h, k| h[k] = [] }

    def self.register(filetype, &block)
      @hooks[filetype] << block
    end

    def self.run(filetype, buffer, editor)
      return unless filetype

      @hooks[filetype].each { |block| block.call(buffer, editor) }
    end

    def self.clear
      @hooks.each_value(&:clear)
    end

    def self.hooks_for(filetype)
      @hooks[filetype].dup
    end
  end
end
