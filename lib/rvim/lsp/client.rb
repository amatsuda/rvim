# frozen_string_literal: true

require 'json'
require 'open3'
require 'thread'

module Rvim
  module Lsp
    # Minimal Language Server Protocol client. Speaks JSON-RPC over stdio
    # to a child process (e.g. `ruby-lsp`). Reads in a background thread and
    # queues incoming messages for the editor to drain on its main loop.
    #
    # Lifecycle: new -> start -> initialize -> ready. Notifications go out
    # via #notify; requests via #request (returns a future-like object that
    # resolves when the matching `id` reply arrives).
    class Client
      # The standard LSP semantic-token legends. Sent in client
      # capabilities so the server knows which types/modifiers we
      # understand; the server may echo a subset as ITS legend, which
      # the editor-side decoder consults to map index -> name.
      SEMANTIC_TOKEN_TYPES = %w[
        namespace type class enum interface struct typeParameter
        parameter variable property enumMember event function method
        macro keyword modifier comment string number regexp operator
        decorator
      ].freeze
      SEMANTIC_TOKEN_MODIFIERS = %w[
        declaration definition readonly static deprecated abstract
        async modification documentation defaultLibrary
      ].freeze

      attr_reader :name, :status, :capabilities, :diagnostics, :window_messages

      # Cap on retained window messages so a chatty server can't grow
      # memory without bound. Old entries fall off the front.
      WINDOW_MESSAGE_LIMIT = 500
      attr_accessor :last_definition_result, :last_hover_result, :last_references_result,
                    :last_formatting_result, :last_document_symbols_result,
                    :last_rename_result, :last_prepare_rename_result,
                    :last_code_actions_result, :last_execute_command_result,
                    :last_code_action_resolve_result, :last_completion_result,
                    :last_inlay_hints_result, :last_workspace_symbols_result,
                    :last_signature_help_result, :last_document_highlights_result,
                    :last_type_definition_result, :last_implementation_result,
                    :last_folding_range_result,
                    :last_call_hierarchy_prepare_result,
                    :last_call_hierarchy_incoming_result,
                    :last_call_hierarchy_outgoing_result,
                    :last_semantic_tokens_result, :last_selection_range_result,
                    :last_code_lens_result, :last_document_link_result,
                    :last_completion_item_resolve_result

      def initialize(name:, command:, root_uri:, on_diagnostic: nil, cwd: nil, on_log: nil)
        @name = name
        @command = command
        @root_uri = root_uri
        @on_diagnostic = on_diagnostic
        @on_log = on_log
        @cwd = cwd
        @status = :stopped
        @next_id = 0
        @pending = {}
        @inbox = Queue.new
        @diagnostics = {} # uri -> array of LSP Diagnostic
        @log_buffer = []  # last N stderr lines (drained by editor pump)
        @window_messages = [] # FIFO of window/log+showMessage entries
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thread = nil
        @reader_thread = nil
        @stderr_thread = nil
        @capabilities = nil
        # Messages sent before the server reaches :running state are
        # queued and flushed after `initialized` goes out, so didOpen
        # can be called as soon as the buffer is loaded.
        @send_queue = []
      end

      def start
        return if @status == :running

        opts = {}
        opts[:chdir] = @cwd if @cwd
        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*Array(@command), opts)
        @stdin.binmode
        @stdout.binmode
        @status = :starting
        @reader_thread = Thread.new { read_loop }
        @stderr_thread = Thread.new { stderr_loop }
        send_initialize
      end

      def log_lines
        @log_buffer.dup
      end

      def stop
        return unless @status == :running || @status == :starting

        notify('shutdown', nil)
        notify('exit', nil)
        @stdin&.close
        @reader_thread&.kill
        @stderr_thread&.kill
        @wait_thread&.kill
        @status = :stopped
      end

      # Process all queued incoming messages. Called from the editor's
      # render loop. Returns the count handled.
      def pump
        n = 0
        until @inbox.empty?
          msg = @inbox.pop(true) rescue nil
          break unless msg

          dispatch(msg)
          n += 1
        end
        n
      end

      def did_open(uri, language_id, version, text)
        notify('textDocument/didOpen', textDocument: {
          uri: uri, languageId: language_id, version: version, text: text,
        })
      end

      # Send a textDocument/didChange. When `range` is provided, the change
      # is encoded as an incremental edit replacing the bytes between
      # range.start and range.end with `text` — required for servers that
      # advertise TextDocumentSyncKind.Incremental (e.g. ruby-lsp 0.26+).
      # When `range` is nil, send the bare `{text}` full-document form,
      # valid for servers using TextDocumentSyncKind.Full.
      def did_change(uri, version, text, range: nil)
        change = { text: text }
        change[:range] = range if range
        notify('textDocument/didChange',
               textDocument: { uri: uri, version: version },
               contentChanges: [change])
      end

      def did_close(uri)
        notify('textDocument/didClose', textDocument: { uri: uri })
      end

      def hover(uri, line, character)
        @last_hover_result = nil
        request('textDocument/hover',
                textDocument: { uri: uri },
                position: { line: line, character: character })
      end

      # textDocument/definition. Result is cached on the client and the
      # caller polls via `last_definition_result`. The response can be a
      # single Location, an array of Locations, an array of LocationLinks,
      # or null.
      def definition(uri, line, character)
        @last_definition_result = nil
        request('textDocument/definition',
                textDocument: { uri: uri },
                position: { line: line, character: character })
      end

      # textDocument/documentLink. Result is DocumentLink[] | null.
      # Each link has `range, target?, tooltip?`. ruby-lsp extracts
      # them from `source://` / `pkg:gem/` magic comments above
      # methods, pointing into stdlib / gem sources.
      def document_link(uri)
        @last_document_link_result = nil
        request('textDocument/documentLink',
                textDocument: { uri: uri })
      end

      # textDocument/codeLens. Result is CodeLens[] | null. Each lens
      # has { range, command?, data? }. When `command` is missing the
      # spec says clients can fetch it via codeLens/resolve, but we
      # don't bother since ruby-lsp returns commands inline.
      def code_lens(uri)
        @last_code_lens_result = nil
        request('textDocument/codeLens',
                textDocument: { uri: uri })
      end

      # textDocument/selectionRange. Result is SelectionRange[] | null,
      # one per input position. Each SelectionRange has `range` and
      # optional `parent` forming a hierarchy from innermost outward.
      def selection_range(uri, line, character)
        @last_selection_range_result = nil
        request('textDocument/selectionRange',
                textDocument: { uri: uri },
                positions: [{ line: line, character: character }])
      end

      # textDocument/semanticTokens/full. Result is
      # { resultId?, data: integer[] } | null. The `data` array is a
      # flat list of 5-tuples (deltaLine, deltaStart, length,
      # tokenType, tokenModifiers) — the editor-side decoder turns
      # them into per-line records using the server's legend.
      def semantic_tokens_full(uri)
        @last_semantic_tokens_result = nil
        request('textDocument/semanticTokens/full',
                textDocument: { uri: uri })
      end

      # textDocument/prepareCallHierarchy. Result is
      # CallHierarchyItem[] | null. The item(s) become the input for
      # the second-step call_hierarchy_incoming / _outgoing requests.
      def prepare_call_hierarchy(uri, line, character)
        @last_call_hierarchy_prepare_result = nil
        request('textDocument/prepareCallHierarchy',
                textDocument: { uri: uri },
                position: { line: line, character: character })
      end

      # callHierarchy/incomingCalls. Input is a CallHierarchyItem from
      # the prepare step; result is CallHierarchyIncomingCall[] | null
      # — each `{ from: CallHierarchyItem, fromRanges: Range[] }`.
      def call_hierarchy_incoming(item)
        @last_call_hierarchy_incoming_result = nil
        request('callHierarchy/incomingCalls', item: item)
      end

      # callHierarchy/outgoingCalls. Result is
      # CallHierarchyOutgoingCall[] | null — each
      # `{ to: CallHierarchyItem, fromRanges: Range[] }`.
      def call_hierarchy_outgoing(item)
        @last_call_hierarchy_outgoing_result = nil
        request('callHierarchy/outgoingCalls', item: item)
      end

      # textDocument/foldingRange. Result is FoldingRange[] | null,
      # where each entry is { startLine, endLine, kind? }. Lines are
      # 0-based; endLine is inclusive (the line of the closing token).
      def folding_range(uri)
        @last_folding_range_result = nil
        request('textDocument/foldingRange',
                textDocument: { uri: uri })
      end

      # textDocument/typeDefinition. Same response shape as definition;
      # the server returns the location of the symbol's TYPE rather
      # than the symbol's own declaration.
      def type_definition(uri, line, character)
        @last_type_definition_result = nil
        request('textDocument/typeDefinition',
                textDocument: { uri: uri },
                position: { line: line, character: character })
      end

      # textDocument/implementation. Same response shape as definition;
      # for an interface / abstract method, the server returns the
      # location(s) of the concrete implementations.
      def implementation(uri, line, character)
        @last_implementation_result = nil
        request('textDocument/implementation',
                textDocument: { uri: uri },
                position: { line: line, character: character })
      end

      # textDocument/references. Result is Location[] | null. The
      # `includeDeclaration` context flag tells the server whether to
      # include the symbol's defining occurrence in the result.
      def references(uri, line, character, include_declaration: true)
        @last_references_result = nil
        request('textDocument/references',
                textDocument: { uri: uri },
                position: { line: line, character: character },
                context: { includeDeclaration: include_declaration })
      end

      # textDocument/formatting. Result is TextEdit[] | null where each
      # TextEdit is { range: Range, newText: string }. ruby-lsp typically
      # returns a single edit replacing the whole document with the
      # formatted version (RuboCop / SyntaxTree).
      def formatting(uri, tab_size: 2, insert_spaces: true)
        @last_formatting_result = nil
        request('textDocument/formatting',
                textDocument: { uri: uri },
                options: { tabSize: tab_size, insertSpaces: insert_spaces })
      end

      # textDocument/documentSymbol. Result is DocumentSymbol[] |
      # SymbolInformation[] | null. The two shapes are returned by
      # different servers; the editor-side flattener handles both.
      def document_symbol(uri)
        @last_document_symbols_result = nil
        request('textDocument/documentSymbol',
                textDocument: { uri: uri })
      end

      # workspace/symbol. Result is SymbolInformation[] |
      # WorkspaceSymbol[] | null — both shapes carry `location` so the
      # editor-side flattener can reuse the documentSymbol path.
      def workspace_symbol(query)
        @last_workspace_symbols_result = nil
        request('workspace/symbol', query: query.to_s)
      end

      # textDocument/prepareRename. When the server advertises
      # `renameProvider.prepareProvider: true`, the client should call
      # this first to validate the symbol at the position. Result is
      # Range | { range, placeholder } | { defaultBehavior: true } | null.
      def prepare_rename(uri, line, character)
        @last_prepare_rename_result = nil
        request('textDocument/prepareRename',
                textDocument: { uri: uri },
                position: { line: line, character: character })
      end

      # textDocument/rename. Result is WorkspaceEdit | null, which the
      # editor applies across (potentially many) files.
      def rename(uri, line, character, new_name)
        @last_rename_result = nil
        request('textDocument/rename',
                textDocument: { uri: uri },
                position: { line: line, character: character },
                newName: new_name)
      end

      # textDocument/codeAction. Result is (Command | CodeAction)[] | null.
      # `diagnostics` is the list of LSP Diagnostic objects relevant to the
      # range; pass [] when invoking without a specific target diagnostic.
      def code_action(uri, range, diagnostics: [])
        @last_code_actions_result = nil
        request('textDocument/codeAction',
                textDocument: { uri: uri },
                range: range,
                context: { diagnostics: diagnostics, triggerKind: 1 })
      end

      # textDocument/documentHighlight. Result is DocumentHighlight[] |
      # null. Each highlight = { range, kind?: 1=Text | 2=Read | 3=Write }.
      def document_highlight(uri, line, character)
        @last_document_highlights_result = nil
        request('textDocument/documentHighlight',
                textDocument: { uri: uri },
                position: { line: line, character: character })
      end

      # textDocument/signatureHelp. Result is SignatureHelp | null.
      # SignatureHelp = { signatures, activeSignature?, activeParameter? }.
      def signature_help(uri, line, character)
        @last_signature_help_result = nil
        request('textDocument/signatureHelp',
                textDocument: { uri: uri },
                position: { line: line, character: character })
      end

      # textDocument/inlayHint. Result is InlayHint[] | null. Each
      # hint has { position: { line, character }, label, kind?,
      # paddingLeft?, paddingRight?, tooltip?, ... }. Label can be a
      # String or an array of InlayHintLabelPart objects.
      def inlay_hint(uri, range)
        @last_inlay_hints_result = nil
        request('textDocument/inlayHint',
                textDocument: { uri: uri },
                range: range)
      end

      # textDocument/completion. Result is CompletionItem[] |
      # CompletionList | null. CompletionList wraps items with a flag
      # for whether the result is complete; we only care about items.
      def completion(uri, line, character)
        @last_completion_result = nil
        request('textDocument/completion',
                textDocument: { uri: uri },
                position: { line: line, character: character },
                context: { triggerKind: 1 })
      end

      # completionItem/resolve. The initial textDocument/completion
      # response is often lightweight — servers fill in `detail`,
      # `documentation`, and `additionalTextEdits` only when asked.
      # The editor sends one resolve per selected candidate so the
      # detail popup shows full docs.
      def completion_item_resolve(item)
        @last_completion_item_resolve_result = nil
        # The JSON-RPC `params` field is the CompletionItem itself —
        # spread its keys through `request`'s **params signature.
        request('completionItem/resolve', **item)
      end

      # codeAction/resolve. Server-deferred actions are returned from
      # textDocument/codeAction with only `data` set (no `edit` /
      # `command`). This request asks the server to fill them in so the
      # client can apply.
      def code_action_resolve(action)
        @last_code_action_resolve_result = nil
        # `request` expects keyword args; LSP spec passes the CodeAction
        # object directly as params, so we send via a low-level path that
        # accepts the whole object.
        id = (@next_id += 1)
        @pending[id] = ['codeAction/resolve', nil]
        body = { jsonrpc: '2.0', id: id, method: 'codeAction/resolve', params: action }
        if @status == :running
          send_message(body)
        else
          @send_queue << body
        end
        id
      end

      # workspace/executeCommand. Result is `any` per spec — servers may
      # return null, edits, or arbitrary data. Fire-and-forget for our v1:
      # the editor doesn't read the result back yet.
      def execute_command(command, arguments = nil)
        @last_execute_command_result = nil
        params = { command: command }
        params[:arguments] = arguments if arguments
        request('workspace/executeCommand', **params)
      end

      # LSP 3.17 pull diagnostics. ruby-lsp 0.26+ uses this rather than
      # pushing publishDiagnostics. Result lands in client.diagnostics
      # under the same uri key, so callers query the same place.
      def request_diagnostics(uri)
        request('textDocument/diagnostic', textDocument: { uri: uri })
      end

      def request(method, **params)
        id = (@next_id += 1)
        @pending[id] = [method, params[:textDocument]&.[](:uri)]
        body = { jsonrpc: '2.0', id: id, method: method, params: params }
        # `initialize` itself must go out before `initialized`; everything
        # else is queued until the server is ready.
        if @status == :running || method == 'initialize'
          send_message(body)
        else
          @send_queue << body
        end
        id
      end

      # Is any request with this method name still waiting for a reply?
      # Used by editor-side polling loops so they can stop waiting once
      # the server has answered (even when the answer is `null`).
      def pending_for?(method_name)
        @pending.any? { |_, entry| (entry.is_a?(Array) ? entry[0] : entry) == method_name }
      end

      def notify(method, params = nil)
        body = { jsonrpc: '2.0', method: method }
        body[:params] = params if params
        if @status == :running || method == 'initialized' || method == 'exit'
          send_message(body)
        else
          @send_queue << body
        end
      end

      private

      def send_initialize
        request('initialize',
                processId: Process.pid,
                rootUri: @root_uri,
                capabilities: client_capabilities,
                initializationOptions: initialization_options,
                clientInfo: { name: 'rvim', version: Rvim::VERSION })
      end

      def client_capabilities
        {
          textDocument: {
            synchronization: { didSave: false, willSave: false, willSaveWaitUntil: false },
            publishDiagnostics: { relatedInformation: true },
            diagnostic: { dynamicRegistration: false, relatedDocumentSupport: false },
            hover: { contentFormat: %w[markdown plaintext] },
            documentHighlight: { dynamicRegistration: false },
            typeDefinition: { dynamicRegistration: false, linkSupport: false },
            implementation: { dynamicRegistration: false, linkSupport: false },
            foldingRange: { dynamicRegistration: false, lineFoldingOnly: true },
            callHierarchy: { dynamicRegistration: false },
            codeLens: { dynamicRegistration: false },
            documentLink: { dynamicRegistration: false, tooltipSupport: true },
            semanticTokens: {
              dynamicRegistration: false,
              requests: { full: true, range: false },
              tokenTypes: SEMANTIC_TOKEN_TYPES,
              tokenModifiers: SEMANTIC_TOKEN_MODIFIERS,
              formats: ['relative'],
              overlappingTokenSupport: false,
              multilineTokenSupport: false,
            },
            signatureHelp: {
              signatureInformation: {
                documentationFormat: %w[markdown plaintext],
                parameterInformation: { labelOffsetSupport: true },
              },
            },
            completion: { completionItem: { snippetSupport: false } },
            inlayHint: { dynamicRegistration: false },
          },
          workspace: {
            workspaceFolders: false,
            symbol: { dynamicRegistration: false },
          },
        }
      end

      # ruby-lsp gates each inlay-hint category behind a feature flag
      # in initializationOptions.featuresConfiguration.inlayHint. With
      # the defaults (both off) textDocument/inlayHint returns []. We
      # opt into both supported categories so users actually see hints.
      def initialization_options
        {
          featuresConfiguration: {
            inlayHint: { implicitRescue: true, implicitHashValue: true },
          },
        }
      end

      def send_message(body)
        return unless @stdin

        json = JSON.generate(body)
        framed = "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
        begin
          @stdin.write(framed)
          @stdin.flush
        rescue Errno::EPIPE, IOError
          @status = :stopped
        end
      end

      def read_loop
        loop do
          headers = read_headers
          break if headers.nil?

          length = headers['Content-Length']&.to_i
          break if length.nil? || length <= 0

          body = @stdout.read(length)
          break if body.nil?

          msg = begin
            JSON.parse(body, symbolize_names: true)
          rescue JSON::ParserError
            nil
          end
          @inbox << msg if msg
        end
      rescue IOError, Errno::EBADF
        # server gone
      end

      def read_headers
        headers = {}
        loop do
          line = @stdout.gets
          return nil if line.nil?

          line = line.chomp("\r\n").chomp("\n")
          break if line.empty?

          k, v = line.split(': ', 2)
          headers[k] = v if k && v
        end
        headers
      end

      def dispatch(msg)
        if msg[:id] && msg[:method].nil?
          # Response.
          handle_response(msg)
        elsif msg[:method]
          handle_notification_or_request(msg)
        end
      end

      def handle_response(msg)
        entry = @pending.delete(msg[:id])
        method, uri = entry.is_a?(Array) ? entry : [entry, nil]
        case method
        when 'initialize'
          @capabilities = msg.dig(:result, :capabilities)
          notify('initialized', {})
          @status = :running
          flush_send_queue
        when 'textDocument/diagnostic'
          # LSP 3.17 pull diagnostics. Result is a DocumentDiagnosticReport:
          #   { kind: "full", items: [...] }                — replace cache
          #   { kind: "unchanged", resultId: "..." }         — keep cache
          # Treat anything without an explicit items array as "unchanged" so
          # repeated pulls don't wipe a previously-populated cache.
          kind = msg.dig(:result, :kind)
          items = msg.dig(:result, :items)
          if uri && kind != 'unchanged' && items
            @diagnostics[uri] = items
            @on_diagnostic&.call(uri, items)
          end
        when 'textDocument/definition'
          # Result is Location | Location[] | LocationLink[] | null.
          # Stash verbatim; the editor-side caller normalizes.
          @last_definition_result = msg[:result]
        when 'textDocument/hover'
          # Result is { contents: MarkedString | MarkedString[] | MarkupContent,
          # range?: Range } | null. Stash verbatim; editor parses contents.
          @last_hover_result = msg[:result]
        when 'textDocument/references'
          # Result is Location[] | null. Stash verbatim.
          @last_references_result = msg[:result]
        when 'textDocument/formatting'
          # Result is TextEdit[] | null. Stash verbatim; editor applies.
          @last_formatting_result = msg[:result]
        when 'textDocument/documentSymbol'
          # Result is DocumentSymbol[] | SymbolInformation[] | null.
          @last_document_symbols_result = msg[:result]
        when 'workspace/symbol'
          # Result is SymbolInformation[] | WorkspaceSymbol[] | null.
          @last_workspace_symbols_result = msg[:result]
        when 'textDocument/rename'
          # Result is WorkspaceEdit | null. Stash verbatim; editor applies.
          @last_rename_result = msg[:result]
        when 'textDocument/prepareRename'
          # Result is Range | { range, placeholder } | { defaultBehavior } | null.
          @last_prepare_rename_result = msg[:result]
        when 'textDocument/codeAction'
          # Result is (Command | CodeAction)[] | null.
          @last_code_actions_result = msg[:result]
        when 'workspace/executeCommand'
          # Result is `any`; stash verbatim.
          @last_execute_command_result = msg[:result]
        when 'codeAction/resolve'
          # Result is a fully-resolved CodeAction (with edit/command).
          @last_code_action_resolve_result = msg[:result]
        when 'textDocument/completion'
          # Result is CompletionItem[] | CompletionList | null.
          @last_completion_result = msg[:result]
        when 'textDocument/inlayHint'
          # Result is InlayHint[] | null.
          @last_inlay_hints_result = msg[:result]
        when 'textDocument/signatureHelp'
          # Result is SignatureHelp | null.
          @last_signature_help_result = msg[:result]
        when 'textDocument/documentHighlight'
          # Result is DocumentHighlight[] | null.
          @last_document_highlights_result = msg[:result]
        when 'textDocument/typeDefinition'
          # Same shape as textDocument/definition.
          @last_type_definition_result = msg[:result]
        when 'textDocument/implementation'
          # Same shape as textDocument/definition.
          @last_implementation_result = msg[:result]
        when 'textDocument/foldingRange'
          # Result is FoldingRange[] | null.
          @last_folding_range_result = msg[:result]
        when 'textDocument/prepareCallHierarchy'
          # Result is CallHierarchyItem[] | null.
          @last_call_hierarchy_prepare_result = msg[:result]
        when 'callHierarchy/incomingCalls'
          # Result is CallHierarchyIncomingCall[] | null.
          @last_call_hierarchy_incoming_result = msg[:result]
        when 'callHierarchy/outgoingCalls'
          # Result is CallHierarchyOutgoingCall[] | null.
          @last_call_hierarchy_outgoing_result = msg[:result]
        when 'textDocument/semanticTokens/full'
          # Result is { resultId?, data: int[] } | null.
          @last_semantic_tokens_result = msg[:result]
        when 'textDocument/selectionRange'
          # Result is SelectionRange[] | null.
          @last_selection_range_result = msg[:result]
        when 'textDocument/codeLens'
          # Result is CodeLens[] | null.
          @last_code_lens_result = msg[:result]
        when 'textDocument/documentLink'
          # Result is DocumentLink[] | null.
          @last_document_link_result = msg[:result]
        when 'completionItem/resolve'
          # Result is the fully-resolved CompletionItem.
          @last_completion_item_resolve_result = msg[:result]
        end
      end

      def flush_send_queue
        queued = @send_queue
        @send_queue = []
        queued.each { |body| send_message(body) }
      end

      def stderr_loop
        return unless @stderr

        while (line = @stderr.gets)
          line = line.chomp
          next if line.empty?

          @log_buffer << line
          @log_buffer.shift while @log_buffer.size > 100
          @on_log&.call(line)
        end
      rescue IOError, Errno::EBADF
        # server gone
      end

      def handle_notification_or_request(msg)
        case msg[:method]
        when 'textDocument/publishDiagnostics'
          uri = msg.dig(:params, :uri)
          diags = msg.dig(:params, :diagnostics) || []
          @diagnostics[uri] = diags
          @on_diagnostic&.call(uri, diags)
        when 'window/logMessage', 'window/showMessage'
          # Capture both into a bounded ring so :LspWatch can stream
          # them to a buffer. Types: 1=Error, 2=Warning, 3=Info, 4=Log.
          record_window_message(
            kind: msg[:method].sub('window/', ''),
            type: msg.dig(:params, :type),
            message: msg.dig(:params, :message).to_s,
          )
        end
      end

      # Append one window/{log,show}Message entry to the bounded ring.
      # `kind` is "logMessage" or "showMessage"; `type` is 1..4.
      def record_window_message(kind:, type:, message:)
        @window_messages << {
          time: Time.now,
          kind: kind,
          type: type.to_i,
          message: message,
        }
        # Drop the oldest entries when over the cap. We're called from
        # the reader thread, but @window_messages is only read by the
        # main thread via #window_messages — single-writer model, GIL
        # makes appends safe enough.
        return if @window_messages.size <= WINDOW_MESSAGE_LIMIT

        @window_messages.shift(@window_messages.size - WINDOW_MESSAGE_LIMIT)
      end
    end
  end
end
