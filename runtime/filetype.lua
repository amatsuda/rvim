-- rvim's bundled filetype detection.
--
-- NeoVim ships an extensive filetype detection table here (see
-- $VIMRUNTIME/lua/vim/filetype.lua). We provide a minimal stub so
-- plugins that source $VIMRUNTIME/filetype.lua at startup (lazy.nvim
-- does this) don't crash; actual filetype detection still works via
-- :setf / :setfiletype from the user's config.

-- Plugins probe vim.filetype.{add,match,get_option} — provide a
-- no-op surface so they can register patterns without erroring.
vim.filetype = vim.filetype or {}

vim.filetype.add = vim.filetype.add or function(_opts)
  -- TODO: store the extension / filename / pattern maps so we can
  -- consult them when a buffer is opened.
end

vim.filetype.match = vim.filetype.match or function(_opts)
  return nil
end

vim.filetype.get_option = vim.filetype.get_option or function(_filetype, _option)
  return nil
end
