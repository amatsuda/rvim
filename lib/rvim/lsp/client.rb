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

      def initialize(name:, command:, root_uri:, on_diagnostic: nil, cwd: nil)
        @name = name
        @command = command
        @root_uri = root_uri
        @on_diagnostic = on_diagnostic
        @cwd = cwd
        @status = :stopped
        @next_id = 0
        @pending = {}
        @inbox = Queue.new
        @diagnostics = {} # uri -> array of LSP Diagnostic
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thread = nil
        @reader_thread = nil
        @capabilities = nil
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
        send_initialize
      end

      def stop
        return unless @status == :running || @status == :starting

        notify('shutdown', nil)
        notify('exit', nil)
        @stdin&.close
        @reader_thread&.kill
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

      def did_change(uri, version, text)
        notify('textDocument/didChange',
               textDocument: { uri: uri, version: version },
               contentChanges: [{ text: text }])
      end

      def did_close(uri)
        notify('textDocument/didClose', textDocument: { uri: uri })
      end

      def hover(uri, line, character)
        request('textDocument/hover',
                textDocument: { uri: uri },
                position: { line: line, character: character })
      end

      def request(method, **params)
        id = (@next_id += 1)
        @pending[id] = method
        send_message(jsonrpc: '2.0', id: id, method: method, params: params)
        id
      end

      def notify(method, params = nil)
        body = { jsonrpc: '2.0', method: method }
        body[:params] = params if params
        send_message(body)
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
        method = @pending.delete(msg[:id])
        case method
        when 'initialize'
          @capabilities = msg.dig(:result, :capabilities)
          notify('initialized', {})
          @status = :running
        end
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
