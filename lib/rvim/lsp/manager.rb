# frozen_string_literal: true

module Rvim
  module Lsp
    # Per-editor manager that maps filetypes to language-server commands and
    # owns one Rvim::Lsp::Client per active language. Buffers register on
    # open (didOpen) and update on change.
    class Manager
      # Filetype symbol -> [command, args...]
      DEFAULT_SERVERS = {
        ruby: %w[ruby-lsp],
      }.freeze

      def initialize(editor)
        @editor = editor
        @clients = {} # ft -> Client
        @servers = DEFAULT_SERVERS.dup
        @buffer_versions = Hash.new(0) # buffer_id -> version
      end

      def register_server(ft, command)
        @servers[ft] = Array(command)
      end

      # Called from editor when a buffer is loaded (BufRead).
      def did_open(buffer)
        ft = filetype_for(buffer)
        return unless ft && @servers.key?(ft)

        client = ensure_client(ft)
        return unless client

        version = (@buffer_versions[buffer.id] += 1)
        client.did_open(buffer_uri(buffer), ft.to_s, version, buffer.lines.join("\n"))
      end

      # Called whenever a buffer's text changes (between edits, before save).
      def did_change(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return unless client && client.status == :running

        version = (@buffer_versions[buffer.id] += 1)
        client.did_change(buffer_uri(buffer), version, buffer.lines.join("\n"))
      end

      def did_close(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return unless client && client.status == :running

        client.did_close(buffer_uri(buffer))
      end

      def diagnostics_for(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return [] unless client

        client.diagnostics[buffer_uri(buffer)] || []
      end

      # Pull-mode diagnostics request (LSP 3.17). ruby-lsp 0.26+ uses
      # this rather than pushing publishDiagnostics. The response is
      # cached under the same uri so diagnostics_for sees it.
      def pull_diagnostics(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.request_diagnostics(buffer_uri(buffer))
        true
      end

      def pump
        @clients.each_value(&:pump)
      end

      def shutdown
        @clients.each_value(&:stop)
        @clients.clear
      end

      def each_client(&block)
        @clients.each_value(&block)
      end

      private

      def ensure_client(ft)
        return @clients[ft] if @clients[ft]

        command = @servers[ft]
        return nil unless command

        root = @editor.respond_to?(:cwd) && @editor.cwd ? @editor.cwd : Dir.pwd
        client = Rvim::Lsp::Client.new(
          name: "#{ft}-lsp",
          command: command,
          root_uri: file_uri(root),
          cwd: root,
        )
        begin
          client.start
        rescue StandardError, SystemCallError => e
          @editor.status_message = "LSP[#{ft}]: failed to start: #{e.message}"
          return nil
        end
        @clients[ft] = client
      end

      def filetype_for(buffer)
        return nil unless buffer&.filepath

        Rvim::Syntax.detect_language(buffer.filepath)
      end

      def buffer_uri(buffer)
        path = buffer.filepath
        return nil unless path

        file_uri(File.expand_path(path))
      end

      def file_uri(path)
        "file://#{path}"
      end
    end
  end
end
