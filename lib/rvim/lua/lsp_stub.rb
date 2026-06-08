# frozen_string_literal: true

module Rvim
  module Lua
    # vim.lsp / vim.diagnostic stubs.
    #
    # rvim doesn't run an LSP client. Many plugins probe for LSP at startup
    # and silently disable themselves when none is found, but they call
    # methods like vim.lsp.get_clients() expecting an empty list — not nil
    # or an error. This file provides those soft-fail entry points so the
    # editor stays usable even when a config tries to wire up LSP.
    module LspStub
      module_function

      LSP_LUA = <<~LUA
        -- vim.lpeg stub. NeoVim 0.10+ exposes the lpeg parsing library
        -- on vim.lpeg. telescope-file-browser's lsp module builds a
        -- glob-pattern grammar at *module load time* (inside a `do`
        -- block), so the module can't even be required without lpeg.
        -- We don't trigger LSP rename events so the grammar is never
        -- consulted; a metatable-driven no-op that swallows every
        -- combinator + arithmetic operator is enough to satisfy the
        -- module-load handshake.
        if vim.lpeg == nil then
          local stub = {}
          local mt = {}
          mt.__index = function() return function() return stub end end
          mt.__call  = function() return stub end
          mt.__add   = function() return stub end
          mt.__sub   = function() return stub end
          mt.__mul   = function() return stub end
          mt.__pow   = function() return stub end
          mt.__div   = function() return stub end
          mt.__unm   = function() return stub end
          mt.__len   = function() return stub end
          setmetatable(stub, mt)
          vim.lpeg = stub
        end

        vim.lsp = vim.lsp or {}
        vim.lsp.handlers   = vim.lsp.handlers or {}
        vim.lsp.protocol   = vim.lsp.protocol or {
          Methods = {
            -- Workspace file ops (used by telescope-file-browser's
            -- lsp module to register willRename / didRename hooks).
            workspace_willCreateFiles = "workspace/willCreateFiles",
            workspace_didCreateFiles  = "workspace/didCreateFiles",
            workspace_willRenameFiles = "workspace/willRenameFiles",
            workspace_didRenameFiles  = "workspace/didRenameFiles",
            workspace_willDeleteFiles = "workspace/willDeleteFiles",
            workspace_didDeleteFiles  = "workspace/didDeleteFiles",
            -- Document ops — common probes.
            textDocument_definition     = "textDocument/definition",
            textDocument_references     = "textDocument/references",
            textDocument_hover          = "textDocument/hover",
            textDocument_completion     = "textDocument/completion",
            textDocument_rename         = "textDocument/rename",
            textDocument_formatting     = "textDocument/formatting",
            textDocument_codeAction     = "textDocument/codeAction",
            textDocument_documentSymbol = "textDocument/documentSymbol",
            workspace_symbol            = "workspace/symbol",
          },
          ErrorCodes = {},
          MessageType = {},
        }
        vim.lsp.log        = vim.lsp.log or { set_level = function() end, get_level = function() return 0 end }
        vim.lsp.log_levels = { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
        vim.lsp.semantic_tokens = vim.lsp.semantic_tokens or { start = function() end, stop = function() end }
        vim.lsp.codelens   = vim.lsp.codelens or { refresh = function() end, run = function() end, display = function() end }
        vim.lsp.inlay_hint = vim.lsp.inlay_hint or { enable = function() end, is_enabled = function() return false end }
        vim.lsp.document_color = vim.lsp.document_color or { enable = function() end }

        function vim.lsp.start(_config) return nil end
        function vim.lsp.start_client(_config) return nil end
        function vim.lsp.stop_client(_id) end
        function vim.lsp.get_clients(_filter) return {} end
        function vim.lsp.get_active_clients(_filter) return {} end
        function vim.lsp.buf_get_clients(_bufnr) return {} end
        function vim.lsp.buf_attach_client(_bufnr, _client_id) return false end
        function vim.lsp.buf_detach_client(_bufnr, _client_id) end
        function vim.lsp.buf_is_attached(_bufnr, _client_id) return false end
        function vim.lsp.buf_request(_bufnr, _method, _params, _handler) return {}, function() end end
        function vim.lsp.buf_request_sync(_bufnr, _method, _params, _timeout) return {}, "no clients" end
        function vim.lsp.buf_request_all(_bufnr, _method, _params, _handler) end
        function vim.lsp.client_is_stopped(_id) return true end
        function vim.lsp.get_client_by_id(_id) return nil end
        function vim.lsp.set_log_level(_lvl) end
        function vim.lsp.get_log_path() return "" end

        vim.lsp.buf = vim.lsp.buf or {}
        local function lsp_buf_noop() end
        for _, name in ipairs({
          "definition", "declaration", "implementation", "type_definition",
          "references", "hover", "signature_help", "rename", "format",
          "code_action", "execute_command", "workspace_symbol", "document_symbol",
          "completion", "incoming_calls", "outgoing_calls", "list_workspace_folders",
          "add_workspace_folder", "remove_workspace_folder",
        }) do vim.lsp.buf[name] = lsp_buf_noop end

        vim.lsp.diagnostic = vim.lsp.diagnostic or {}
        function vim.lsp.diagnostic.get(_bufnr, _opts) return {} end
        function vim.lsp.diagnostic.set(_diagnostics, _bufnr, _ns, _opts) end

        vim.diagnostic = vim.diagnostic or {}
        vim.diagnostic.severity = { ERROR = 1, WARN = 2, INFO = 3, HINT = 4 }
        function vim.diagnostic.config(_opts) end
        function vim.diagnostic.get(_bufnr, _opts) return {} end
        function vim.diagnostic.set(_ns, _bufnr, _diagnostics, _opts) end
        function vim.diagnostic.show(_ns, _bufnr, _diagnostics, _opts) end
        function vim.diagnostic.hide(_ns, _bufnr) end
        function vim.diagnostic.reset(_ns, _bufnr) end
        function vim.diagnostic.goto_next(_opts) end
        function vim.diagnostic.goto_prev(_opts) end
        function vim.diagnostic.open_float(_bufnr, _opts) end
        function vim.diagnostic.setloclist(_opts) end
        function vim.diagnostic.setqflist(_opts) end
        function vim.diagnostic.enable(_bufnr, _ns) end
        function vim.diagnostic.disable(_bufnr, _ns) end
        function vim.diagnostic.is_disabled(_bufnr, _ns) return true end
      LUA

      def install(state, _editor, _runtime)
        state.eval(LSP_LUA)
      end
    end
  end
end
