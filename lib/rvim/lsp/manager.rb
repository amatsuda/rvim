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
        @last_pulled_at = {} # buffer_id -> monotonic time of last pull request
        @synced_fingerprints = {} # buffer_id -> Array#hash of last synced lines
        @synced_at = {} # buffer_id -> monotonic time of last didChange
        @synced_end_pos = {} # buffer_id -> { line:, character: } end of last synced doc
      end

      # Refresh interval (seconds) for the auto-pull below.
      DIAG_PULL_INTERVAL = 0.5
      # Debounce window (seconds) for didChange. NeoVim uses ~0.15s.
      CHANGE_DEBOUNCE_INTERVAL = 0.15

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
        # Seed the fingerprint so the first note_change tick after open is a
        # no-op — we just sent the full document via didOpen.
        @synced_fingerprints[buffer.id] = buffer.lines.hash
        @synced_end_pos[buffer.id] = end_position_for(buffer.lines)
      end

      # Called whenever a buffer's text changes (between edits, before save).
      # ruby-lsp 0.26+ uses TextDocumentSyncKind.Incremental and silently
      # ignores bare-`{text}` change events, so we always send a range that
      # spans the OLD document and the new full text as the replacement.
      def did_change(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return unless client && client.status == :running

        version = (@buffer_versions[buffer.id] += 1)
        prev_end = @synced_end_pos[buffer.id] || { line: 0, character: 0 }
        range = { start: { line: 0, character: 0 }, end: prev_end }
        client.did_change(buffer_uri(buffer), version, buffer.lines.join("\n"),
                          range: range)
        @synced_end_pos[buffer.id] = end_position_for(buffer.lines)
      end

      def did_close(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        @synced_fingerprints.delete(buffer.id)
        @synced_at.delete(buffer.id)
        @synced_end_pos.delete(buffer.id)
        return unless client && client.status == :running

        client.did_close(buffer_uri(buffer))
      end

      # Called once per render tick (cheap when nothing changed).
      # Compares the buffer's current line-array fingerprint against the
      # last one we synced to the server; if different, sends didChange,
      # debounced so a fast typist doesn't generate one notification per
      # keystroke.
      def note_change(buffer)
        return false unless buffer

        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        fp = buffer.lines.hash
        return false if @synced_fingerprints[buffer.id] == fp

        last = @synced_at[buffer.id]
        return false if last && monotonic_now - last < CHANGE_DEBOUNCE_INTERVAL

        did_change(buffer)
        @synced_fingerprints[buffer.id] = fp
        @synced_at[buffer.id] = monotonic_now
        true
      end

      def diagnostics_for(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return [] unless client

        client.diagnostics[buffer_uri(buffer)] || []
      end

      # { 0-based line => max severity (1=error highest, 4=hint lowest) }.
      # The renderer uses this to decide whether to draw a sign and which glyph.
      def diagnostic_signs(buffer)
        out = {}
        diagnostics_for(buffer).each do |d|
          sl = d.dig(:range, :start, :line)
          sev = d[:severity] || 3
          next unless sl

          cur = out[sl]
          # Lower severity number == more severe; keep the smallest seen.
          out[sl] = sev if cur.nil? || sev < cur
        end
        out
      end

      # { 0-based line => [{first_col, last_col, severity}, ...] } where the
      # cols are byte offsets into the line and last_col is exclusive. Multi-line
      # diagnostics are clipped to one row each (start row spans start.character
      # to end-of-line; end row spans 0 to end.character; intermediate rows span 0..-1).
      def diagnostic_ranges(buffer)
        out = Hash.new { |h, k| h[k] = [] }
        lines = buffer.lines
        diagnostics_for(buffer).each do |d|
          sl = d.dig(:range, :start, :line)
          sc = d.dig(:range, :start, :character).to_i
          el = d.dig(:range, :end, :line)
          ec = d.dig(:range, :end, :character).to_i
          sev = d[:severity] || 3
          next unless sl && el

          if sl == el
            out[sl] << { first_col: sc, last_col: ec, severity: sev }
          else
            sl_text = lines[sl] || ''
            out[sl] << { first_col: sc, last_col: sl_text.bytesize, severity: sev }
            ((sl + 1)...el).each do |li|
              row_text = lines[li] || ''
              out[li] << { first_col: 0, last_col: row_text.bytesize, severity: sev }
            end
            out[el] << { first_col: 0, last_col: ec, severity: sev }
          end
        end
        out.each_value { |arr| arr.sort_by! { |r| r[:first_col] } }
        out
      end

      # Pull-mode diagnostics request (LSP 3.17). ruby-lsp 0.26+ uses
      # this rather than pushing publishDiagnostics. The response is
      # cached under the same uri so diagnostics_for sees it.
      def pull_diagnostics(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.request_diagnostics(buffer_uri(buffer))
        @last_pulled_at[buffer.id] = monotonic_now
        true
      end

      # Periodic auto-pull for the renderer's signcolumn/underline display.
      # ruby-lsp's analysis is asynchronous, so the first pull after didOpen
      # may return empty results — we re-pull at DIAG_PULL_INTERVAL until the
      # server has something to report. Cheap on the wire and in the server
      # (results are cached server-side once analysis completes).
      def maybe_pull_diagnostics(buffer)
        return false unless buffer

        last = @last_pulled_at[buffer.id]
        return false if last && monotonic_now - last < DIAG_PULL_INTERVAL

        pull_diagnostics(buffer)
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

      # End-of-document position in 0-based LSP coordinates. character is
      # the character count of the last line; this matches UTF-16 code
      # units for ASCII + BMP content and is acceptable for surrogate-pair
      # rare cases (we never advertise a different positionEncoding).
      def end_position_for(lines)
        return { line: 0, character: 0 } if lines.nil? || lines.empty?

        { line: lines.size - 1, character: (lines.last || '').size }
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
