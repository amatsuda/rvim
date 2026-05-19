# frozen_string_literal: true

# Pin the process to UTF-8 at both ends so every boundary (file IO, backticks,
# Open3, network, etc.) hands us strings already labeled correctly, instead
# of ASCII-8BIT or whatever LANG happened to be. Internal storage stays
# byte-addressed (vim's @byte_pointer model), but the *labels* are now
# uniform — String#split, regex, and friends never trip on mismatched tags.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'reline'

module Rvim
  # Absolute path to the bundled runtime/ directory. NeoVim ships
  # one of these at $VIMRUNTIME and many plugins (lazy.nvim, anything
  # touching filetype detection or colorschemes) read from it. We
  # ship a minimal version next to lib/.
  RUNTIME_PATH = File.expand_path('../runtime', __dir__).freeze
end

require_relative 'rvim/version'
require_relative 'rvim/job'
require_relative 'rvim/job_registry'
require_relative 'rvim/fs_watcher'
require_relative 'rvim/fs_event_registry'
require_relative 'rvim/highlight_groups'
require_relative 'rvim/async_command'
require_relative 'rvim/selection'
require_relative 'rvim/text_object'
require_relative 'rvim/operations'
require_relative 'rvim/search'
require_relative 'rvim/registers'
require_relative 'rvim/system_clipboard'
require_relative 'rvim/marks'
require_relative 'rvim/folds'
require_relative 'rvim/diff'
require_relative 'rvim/reformat'
require_relative 'rvim/buffer'
require_relative 'rvim/window'
require_relative 'rvim/tab'
require_relative 'rvim/settings'
require_relative 'rvim/highlights'
require_relative 'rvim/syntax'
require_relative 'rvim/syntax/ruby'
require_relative 'rvim/syntax/markdown'
require_relative 'rvim/syntax/json'
require_relative 'rvim/syntax/shell'
require_relative 'rvim/syntax/python'
require_relative 'rvim/syntax/javascript'
require_relative 'rvim/syntax/yaml'
require_relative 'rvim/list_view'
require_relative 'rvim/file_type'
require_relative 'rvim/statusline'
require_relative 'rvim/ftplugins'
require_relative 'rvim/keymap'
require_relative 'rvim/abbreviations'
require_relative 'rvim/filter'
require_relative 'rvim/completion'
require_relative 'rvim/completion_popup'
require_relative 'rvim/cmdline_completion'
require_relative 'rvim/autocommands'
require_relative 'rvim/modeline'
require_relative 'rvim/match_motion'
require_relative 'rvim/text_motion'
require_relative 'rvim/display_motion'
require_relative 'rvim/spell'
require_relative 'rvim/digraphs'
require_relative 'rvim/tags'
require_relative 'rvim/quickfix'
require_relative 'rvim/errorformat'
require_relative 'rvim/undo_file'
require_relative 'rvim/lsp/client'
require_relative 'rvim/lsp/manager'
require_relative 'rvim/lua/runtime'
require_relative 'rvim/lua/bridge'
require_relative 'rvim/lua/cmd'
require_relative 'rvim/lua/notify'
require_relative 'rvim/lua/opt'
require_relative 'rvim/lua/vars'
require_relative 'rvim/lua/keymap'
require_relative 'rvim/lua/api'
require_relative 'rvim/lua/loader'
require_relative 'rvim/lua/fn'
require_relative 'rvim/lua/util'
require_relative 'rvim/lua/ui'
require_relative 'rvim/lua/loop'
require_relative 'rvim/lua/job'
require_relative 'rvim/lua/lsp_stub'
require_relative 'rvim/lua/fs'
require_relative 'rvim/lua/json'
require_relative 'rvim/command'
require_relative 'rvim/screen'
require_relative 'rvim/editor'
