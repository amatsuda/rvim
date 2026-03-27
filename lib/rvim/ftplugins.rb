# frozen_string_literal: true

require_relative 'file_type'

# Built-in filetype defaults. These set per-buffer shiftwidth values that
# match common community conventions.

Rvim::FileType.register(:ruby) do |buffer, editor|
  editor.settings.set(:shiftwidth, 2, buffer: buffer)
end

Rvim::FileType.register(:markdown) do |buffer, editor|
  editor.settings.set(:shiftwidth, 2, buffer: buffer)
end

Rvim::FileType.register(:json) do |buffer, editor|
  editor.settings.set(:shiftwidth, 2, buffer: buffer)
end

Rvim::FileType.register(:shell) do |buffer, editor|
  editor.settings.set(:shiftwidth, 4, buffer: buffer)
end
