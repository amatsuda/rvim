# Rvim v1.14 — User Config, Command History, ignorecase/smartcase

## Why

After v1.13's polish, the editor is functionally complete for editing tasks. The biggest remaining usability gap is statelessness across sessions: every launch starts with the same defaults, every prior `:` command is forgotten, and search is always case-sensitive. Real daily use needs three things that all touch the prompt subsystem we already have:

1. **`~/.rvimrc`** — persists `:set` / future `:map` choices across sessions.
2. **`:history` + arrow-key recall** — bring back the last N ex commands.
3. **`ignorecase` / `smartcase`** — Vim's standard search casing semantics.

These are independent in implementation but they live in the same neighborhood (Settings, prompt input, Search). One small release.

## Out of scope

- `:map` / `:nmap` / `:imap` — key remapping. Useful but a much bigger surface; defer.
- Search history ring (`/abc` ↑↓). Same machinery as ex history; doable but expanded scope. Land ex history first; mirror to search later.
- `q:` command-line window. Niche; the `:history` listing covers the actual use case.
- Lua / vimscript evaluation. Rvimrc is a stream of ex commands, period.
- `XDG_CONFIG_HOME` lookup. `~/.rvimrc` only — keep it stupid simple.

## Architecture

### Sourcing

Add `Rvim::Editor#source(path)`: opens the file, splits into lines, for each line:

- strip trailing newline
- skip blank lines and lines whose first non-whitespace char is `"` (Vim comment) or `#`
- call `Rvim::Command.parse(line)` and `Rvim::Command.execute(self, parsed)`

Errors during a single line update `@status_message` (matching `:` behavior), but processing continues. If the file can't be opened, emit `E484: Can't open file <path>` to status.

`:source path` (verb `:source`, alias `:so`) routes through this same method.

`Editor.start` calls `editor.source(File.expand_path('~/.rvimrc'))` if the file exists, **after** the editor is constructed but **before** the first render. Add a `--norc` flag (and `-u NONE` Vim-compat alias) to `exe/rvim` to skip auto-sourcing — useful for tests and quick experiments.

### ignorecase / smartcase

Add to `Settings::DEFAULTS`:
- `ignorecase: false` (alias `ic`)
- `smartcase: false` (alias `scs`)

Threading: `Rvim::Search.compile` becomes `compile(pattern_str, ignorecase: false)`. Caller (Editor) reads the two settings and computes the effective ignorecase: `ignorecase && !(smartcase && pattern =~ /[A-Z]/)`. Pass as Regexp::IGNORECASE flag.

Sites to update:
- `Editor#scan_search_pattern` (and ad-hoc scans inside `commit_search`, `search_word_under_cursor`, `refresh_incremental_search`)
- `Command.execute_substitute` — `i` flag in `s/pat/rep/i` already exists; OR with global ignorecase setting.

Note: `*` / `#` build a `\bword\b` pattern with literal word — case sensitivity should follow `ignorecase` as well.

### Ex command history

Add `Editor#ex_history` — a bounded array (default cap 100). On successful `execute_prompt` for `:ex`, push `@prompt_buffer.dup` if non-empty and not equal to the last entry. On the prompt input path (the one that handles `\r`, `\e`, backspace, etc.), add:

- Up arrow (key sequence `\e[A` / Reline `:ed_prev_history` symbol after CSI-decoded) → cycle backward, replace `@prompt_buffer` with the recalled command, set `@history_cursor`.
- Down arrow (`\e[B`) → cycle forward; past newest, restore the user-typed draft (kept in `@history_pending`).
- Any non-arrow key edits the buffer normally and clears `@history_cursor`.

Reline's input pipeline already emits keys as decoded escape sequences. The prompt path receives raw bytes (`update_prompt` reads `key.combined_char`/string). We need to detect `\e[A` / `\eOA` (and `\e[B` / `\eOB`) from the multi-byte key string. Reline's `Key` struct exposes `.char` (decoded codepoint or escape) and `.combined_char`. Inspect what we actually get with a probe and dispatch.

`:history` (and `:his`) — show the list via `editor.show_list(format_history(editor))`.

### Persistence

Ex history is **session-scoped** in v1.14. Persisting across launches needs a viminfo-equivalent and is its own design exercise. Documented but deferred.

## Stage breakdown

### Stage 1 — `:source` + script parser

- `Editor#source(path)` — public; reads file, dispatches lines through Command.
- `Command` verb `:source` / `:so` → calls `editor.source(arg)`.
- Comment + blank handling inside `source`.
- Error: missing file → status; per-line errors continue.

**Verify**: `:source /tmp/cmds` runs `set number\nset shiftwidth=4` and both stick.

### Stage 2 — Auto-source `~/.rvimrc`

- `Editor.start` calls `editor.source(File.expand_path('~/.rvimrc'))` if `File.exist?` AND not `--norc`.
- `exe/rvim` argv parsing: extract `--norc` / `-u NONE` before the file list; pass through to `Editor.start(*paths, norc: bool)`.

**Verify**: drop `set number` into `~/.rvimrc`, launch rvim on a file → line numbers visible. Launch with `--norc` → no numbers.

### Stage 3 — ignorecase / smartcase

- Add to Settings DEFAULTS + ALIASES.
- `Search.compile(pat, ignorecase:)` updated.
- Editor helper `private def search_compile_options` returning `{ ignorecase: ... }` based on settings + pattern.
- Plumb through every search/scan call site.
- Substitute: OR setting into the per-command `i` flag.

**Verify**: `:set ignorecase` then `/Foo` matches `foo`. With `:set smartcase` and `/Foo` matches only `Foo`. `:set noignorecase` returns to default.

### Stage 4 — Ex history + arrows + `:history`

- `@ex_history`, `@history_cursor`, `@history_pending` ivars.
- Push on Enter (in `execute_prompt` :ex branch).
- In `update_prompt`, intercept up/down — but only when `@prompt_mode == :ex` (search history is out of scope).
- `Command` verb `:history` / `:his` → list via show_list.

**Verify**: type `:set number`, Enter. Type `:set nu`. Press `:`, then ↑ — last command appears. ↑ again — earlier. Edit and Enter creates new entry. `:history` shows them.

### Stage 5 — Tests + PTY e2e

- Unit: source parser (comment/blank/error handling), settings ic/scs, history push+cycle.
- PTY: rvimrc auto-load, `--norc`, smartcase /Foo, history recall via ↑.

**Verify**: `bundle exec rake` green; PTY script green.

## Risks

1. **Up-arrow detection in our prompt input path**. Reline maps `\e[A` to the `ed_prev_history` symbol *for the inner LineEditor*, but we own `update_prompt`. We may receive the raw byte string `"\e[A"` or a `Reline::Key` with `.char == :ed_prev_history`. Stage 4 starts with a small probe to confirm shape.
2. **`:source` recursion**. A rvimrc that `:source`s itself loops. Mitigate with a depth counter (max 10) — cheap and matches Vim's behavior.
3. **`~/.rvimrc` writes during sourcing**. If the user puts a `:e other.txt` in their rc, the editor opens that file at startup. That's a feature, not a bug, but worth knowing. We do auto-source AFTER `editor.open(path)` for argv files, so argv wins.
