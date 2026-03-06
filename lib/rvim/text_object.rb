# frozen_string_literal: true

module Rvim
  module TextObject
    module_function

    def find(key, editor, inclusive:)
      char = key.is_a?(Integer) ? key.chr : key.to_s
      case char
      when 'w' then word(editor, inclusive: inclusive, big: false)
      when 'W' then word(editor, inclusive: inclusive, big: true)
      when '"', "'", '`' then quote(editor, char, inclusive: inclusive)
      when '(', ')', 'b' then bracket(editor, '(', ')', inclusive: inclusive)
      when '[', ']' then bracket(editor, '[', ']', inclusive: inclusive)
      when '{', '}', 'B' then bracket(editor, '{', '}', inclusive: inclusive)
      when '<', '>' then bracket(editor, '<', '>', inclusive: inclusive)
      when 'p' then paragraph(editor, inclusive: inclusive)
      end
    end

    # Stub — fleshed out in Stage 3.
    def word(editor, inclusive:, big:)
      nil
    end

    # Stub — fleshed out in Stage 4.
    def quote(editor, char, inclusive:)
      nil
    end

    # Stub — fleshed out in Stage 5.
    def bracket(editor, open_ch, close_ch, inclusive:)
      nil
    end

    # Stub — fleshed out in Stage 6.
    def paragraph(editor, inclusive:)
      nil
    end
  end
end
