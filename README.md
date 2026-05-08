# rvim

A pure-Ruby NeoVim-compatible text editor.

`rvim` is a terminal text editor written in Ruby on top of [Reline](https://github.com/ruby/reline). It speaks the same vi keys, ex commands, and configuration files as Vim and NeoVim — drop your `init.vim` or `init.lua` into `~/.config/rvim/` and most of it just works.

## Why

Because it's possible. Reline already implements a sophisticated terminal line editor in Ruby — extending it into a full-screen modal editor turns out to be a finite amount of work. The result is a ~10k-line single-file-install editor with no C compilation, no Vimscript runtime, and a Lua plugin layer that runs unmodified config from a NeoVim setup.

## Install

```sh
gem install rvim
```

For Lua plugin support (optional), install LuaJIT:

```sh
brew install luajit             # macOS
apt install libluajit-5.1-dev   # Debian / Ubuntu
```

## Quick start

```sh
rvim                # open an empty [No Name] buffer
rvim file.rb        # edit a file
rvim a.rb b.rb      # multiple files (use :n / :prev / :argdo)
rvim -u NONE file   # skip rc files
rvim --norc file    # same
```

The keybindings and ex commands match Vim/NeoVim. If you've used either, you already know how to use rvim.

## Configuration

rvim reads config from, in order:

1. `~/.rvimrc` (legacy single-file rc)
2. `$XDG_CONFIG_HOME/rvim/init.vim` (vim-script)
3. `$XDG_CONFIG_HOME/rvim/init.lua` (Lua, NeoVim-compatible)

`~/.config/rvim/` is automatically prepended to `&runtimepath`, so `require('plugin')` from `init.lua` resolves under `~/.config/rvim/lua/`. `~/.config/rvim/after/` is appended for overrides — exactly like NeoVim.

Example `init.lua`:

```lua
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true

vim.g.mapleader = " "
vim.keymap.set("n", "<leader>w", ":write<CR>", { silent = true })
vim.keymap.set("n", "<leader>q", ":quit<CR>")

vim.api.nvim_create_autocmd("BufRead", {
  pattern = "*.rb",
  callback = function()
    vim.bo.shiftwidth = 2
  end,
})
```

Plus a regular `~/.config/rvim/init.vim`:

```vim
set hlsearch
set ignorecase smartcase
set splitright splitbelow
nmap Y y$
inoremap jk <Esc>
```

## What works

**Modes:** normal, insert, replace, visual char/line/block, command-line, search, ex-input (`:a`/`:i`/`:c`).

**Motions:** `hjkl`, `w/W/b/B/e/E/ge/gE`, `0/^/$/g_`, `gg/G`, `H/M/L`, `Ctrl-F/B/D/U`, `f/F/t/T/;/,`, `n/N/*/#/g*/g#`, `%`, `()`/`{}`, `[{`/`]}`, `gj`/`gk` (display motion preserves visual column across multibyte lines), counts on all of them.

**Operators:** `d/c/y` with motions, `~/gu/gU/g~`, `>/<`, `=`, `gq{motion}` reformat, `!{motion}cmd` filter.

**Text objects:** `aw/iw`, `aW/iW`, `as/is`, `ap/ip`, `a"/i"`, `a'/i'`, `` a` ``/`` i` ``, `ab`/`ib`, `aB`/`iB`, `a[`/`i[`, `a<`/`i<`, `at`/`it`.

**Editing:** `i/a/I/A/o/O/r/R/s/S/x/X/p/P/J/u/Ctrl-R/.`, dot repeat, registers (named, numbered, `:`/`=`/`+`/`*`/`%`), block-insert (`Ctrl-V` + `I`/`A`).

**Ex commands:** `:w/:q/:wq/:e/:r`, `:s` substitute, `:%s`, `:g/v`, `:!cmd`, `:%!cmd`, `:r !cmd`, `:source`, `:luafile`, `:lua`, `:set` (260 settings), `:map` family, `:noremap`, `:abbrev`/`:iabbrev`/`:cabbrev`, `:autocmd`/`:augroup`, `:make`/`:grep`/`:vimgrep`/`:lvimgrep`, `:copen`/`:cnext`/`:cprev`, `:lopen`/`:lnext`, `:tag`/`:tags`, `:diffsplit`/`:diffthis`, `:fold`/`:foldopen`/`:foldclose`, `:command`/`:delcommand`, `:runtime`/`:packadd`, `:execute`/`:silent`/`:verbose`/`:redir`/`:messages`, `:earlier`/`:later`/`:undolist`, `:mksession`/`:badd`, `:terminal`, `:help`, `:earlier`, `:bufdo`/`:tabdo`/`:windo`/`:argdo`, `:registers`, `:digraphs`, `:colorscheme`, `:highlight`, `:a`/`:i`/`:c` (line input).

**Windows / tabs:** `:split`/`:vsplit`, `Ctrl-W h/j/k/l`, `:resize`, `Ctrl-W +/-/>/<` and `=`, `:tabnew/:tabclose/:tabnext`, `gt/gT`.

**Search:** `/`, `?`, `n`, `N`, `*`, `#`, `g*`, `g#`; `incsearch`, `hlsearch`, `ignorecase`, `smartcase`, `wrapscan`, `gn`/`gN` visual select.

**Folding:** manual / indent / marker, `zf/zo/zc/za/zd`, foldlevel commands.

**Syntax highlighting:** Ruby, shell, JSON, Markdown, Python, JavaScript/TypeScript, YAML.

**Lua API (NeoVim-compatible subset):** `vim.cmd`, `vim.opt`/`bo`/`wo`/`go`, `vim.g`/`b`/`w`/`t`, `vim.keymap.set/del` (with function rhs), `vim.api.nvim_create_autocmd`/`nvim_create_augroup`, `vim.api.nvim_buf_*` (lines, name, options, vars), `vim.api.nvim_win_*` (cursor, height, width, buf), `vim.api.nvim_*` extended (~30 more), `vim.fn` (~30 builtins), `vim.tbl_*`/`vim.list_*`/`vim.split`/`vim.startswith`, `vim.ui.input`/`vim.ui.select`, `vim.loop` / `vim.uv` (timers, defer_fn, schedule), `vim.notify`, `vim.lsp` and `vim.diagnostic` soft-fail stubs so probe-and-skip plugins don't crash.

`require('mod')` resolves via `&runtimepath` walking `lua/mod.lua` and `lua/mod/init.lua`, mirroring NeoVim.

## What does NOT work

- **LSP** — `vim.lsp.*` is a soft-fail stub; rvim doesn't implement an LSP client.
- **Tree-sitter** — `vim.treesitter.*` is not implemented; syntax highlighting uses regex modules.
- **Async / job control** — `vim.fn.jobstart` and persistent shell jobs aren't supported. `vim.loop` covers timers and `defer_fn` only.
- **Plugin managers like lazy.nvim / packer.nvim** — these need git/curl-driven install plus rocks; out of scope.
- **Telescope** — depends on async previewers and LSP.
- **Modern UI plugins that hook the real `vim.api`** — partial support; many work, some don't.

In short: simple plugins (themes, statuslines, motion helpers, simple text-manip) tend to work. Anything that integrates with LSP or treesitter or async I/O does not.

## Project structure

```
exe/rvim                    main entrypoint
lib/rvim.rb                 setup + UTF-8 encoding pin
lib/rvim/editor.rb          the Editor (subclass of Reline::LineEditor)
lib/rvim/screen.rb          ANSI screen renderer
lib/rvim/command.rb         ex-command parser + dispatch
lib/rvim/settings.rb        260 vim settings + aliases
lib/rvim/keymap.rb          mapping table + key-name expansion
lib/rvim/abbreviations.rb   :abbrev / :iabbrev / :cabbrev
lib/rvim/autocommands.rb    :autocmd / :augroup
lib/rvim/folds.rb           manual + indent + marker folds
lib/rvim/syntax/            per-language regex highlighters
lib/rvim/lua/               Lua runtime + per-namespace bridges
lib/rvim/help/help.txt      bundled :help cheat-sheet
test/                       1600+ tests (Test::Unit)
```

## Running the tests

```sh
bundle install
bundle exec rake test
```

Tests use Test::Unit and run in 4–5 seconds. The Lua tests automatically skip when no Lua 5.1 dynamic library is installed.

## License

MIT — see [LICENSE](LICENSE).
