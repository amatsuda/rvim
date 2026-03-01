# frozen_string_literal: true

module Rvim
  class Editor
    def self.start(filepath = nil)
      puts "rvim #{Rvim::VERSION}"
      _ = filepath
    end
  end
end
