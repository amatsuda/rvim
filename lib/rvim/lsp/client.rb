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
      attr_reader :name, :status, :capabilities, :diagnostics
      attr_accessor :last_definition_result, :last_hover_result

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
                clientInfo: { name: 'rvim', version: Rvim::VERSION })
      end

      def client_capabilities
        {
          textDocument: {
            synchronization: { didSave: false, willSave: false, willSaveWaitUntil: false },
            publishDiagnostics: { relatedInformation: true },
            diagnostic: { dynamicRegistration: false, relatedDocumentSupport: false },
            hover: { contentFormat: %w[markdown plaintext] },
            completion: { completionItem: { snippetSupport: false } },
          },
          workspace: { workspaceFolders: false },
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
          # Could surface to editor.status_message; skip for v1 to avoid noise.
        end
      end
    end
  end
end
