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
        @last_hints_pulled_at = {} # buffer_id -> monotonic time of last inlayHint pull
        @inlay_hints_cache = {} # buffer_id -> InlayHint[]
      end

      # Refresh interval (seconds) for the diagnostic auto-pull below.
      DIAG_PULL_INTERVAL = 0.5
      # Refresh interval (seconds) for the inlay-hint auto-pull.
      HINTS_PULL_INTERVAL = 1.0
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

      # Send textDocument/definition for the cursor's current position in
      # `buffer`. The response (Location/Location[]/LocationLink[]/null) is
      # stashed on the client; callers poll via #last_definition_result.
      def request_definition(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.definition(buffer_uri(buffer),
                          @editor.line_index, @editor.byte_pointer)
        true
      end

      def last_definition_result
        @clients.each_value do |c|
          r = c.last_definition_result
          return r if r
        end
        nil
      end

      def clear_definition_result
        @clients.each_value { |c| c.last_definition_result = nil }
      end

      # Send textDocument/hover for the cursor's current position.
      # Result lands on the client; callers poll via #last_hover_result.
      def request_hover(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.hover(buffer_uri(buffer),
                     @editor.line_index, @editor.byte_pointer)
        true
      end

      def last_hover_result
        @clients.each_value do |c|
          r = c.last_hover_result
          return r if r
        end
        nil
      end

      def clear_hover_result
        @clients.each_value { |c| c.last_hover_result = nil }
      end

      # Send textDocument/references for the cursor's current position.
      # Result lands on the client; callers poll via #last_references_result.
      def request_references(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.references(buffer_uri(buffer),
                          @editor.line_index, @editor.byte_pointer)
        true
      end

      def last_references_result
        @clients.each_value do |c|
          r = c.last_references_result
          return r if r
        end
        nil
      end

      def clear_references_result
        @clients.each_value { |c| c.last_references_result = nil }
      end

      # Send textDocument/formatting for the buffer using the editor's
      # current tabstop / expandtab settings. Result lands on the client.
      def request_formatting(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        ts = (@editor.settings.get(:tabstop).to_i if @editor.respond_to?(:settings)) || 2
        ts = 2 if ts <= 0
        insert_spaces = !!(@editor.respond_to?(:settings) && @editor.settings.get(:expandtab))
        client.formatting(buffer_uri(buffer), tab_size: ts, insert_spaces: insert_spaces)
        true
      end

      def last_formatting_result
        @clients.each_value do |c|
          r = c.last_formatting_result
          return r if r
        end
        nil
      end

      def clear_formatting_result
        @clients.each_value { |c| c.last_formatting_result = nil }
      end

      # Send textDocument/documentSymbol for the buffer. Result lands on
      # the client; callers poll via #last_document_symbols_result.
      def request_document_symbols(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.document_symbol(buffer_uri(buffer))
        true
      end

      def last_document_symbols_result
        @clients.each_value do |c|
          r = c.last_document_symbols_result
          return r if r
        end
        nil
      end

      def clear_document_symbols_result
        @clients.each_value { |c| c.last_document_symbols_result = nil }
      end

      # Send textDocument/rename for the cursor's current position with
      # `new_name`. Result lands on the client as a WorkspaceEdit.
      def request_rename(buffer, new_name)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.rename(buffer_uri(buffer),
                      @editor.line_index, @editor.byte_pointer,
                      new_name)
        true
      end

      # Send textDocument/prepareRename to validate that the symbol at
      # the cursor can be renamed by this server. Returns true on
      # successful dispatch, false when no client / not running. The
      # response lands as Range | { range, placeholder } |
      # { defaultBehavior: true } | null on the client.
      def request_prepare_rename(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.prepare_rename(buffer_uri(buffer),
                              @editor.line_index, @editor.byte_pointer)
        true
      end

      def last_prepare_rename_result
        @clients.each_value do |c|
          r = c.last_prepare_rename_result
          return r if r
        end
        nil
      end

      def clear_prepare_rename_result
        @clients.each_value { |c| c.last_prepare_rename_result = nil }
      end

      # Send textDocument/codeAction for the current cursor position.
      # The range collapses to a single point at the cursor; diagnostics
      # on the cursor's line are passed as context so the server's
      # quickfix-style actions surface. Result lands on the client.
      def request_code_actions(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        line = @editor.line_index
        char = @editor.byte_pointer
        range = { start: { line: line, character: char },
                  end:   { line: line, character: char } }
        # Include diagnostics on the cursor's line as context.
        diags = diagnostics_for(buffer).select do |d|
          sl = d.dig(:range, :start, :line)
          el = d.dig(:range, :end, :line)
          sl && el && line.between?(sl.to_i, el.to_i)
        end
        client.code_action(buffer_uri(buffer), range, diagnostics: diags)
        true
      end

      def last_code_actions_result
        @clients.each_value do |c|
          r = c.last_code_actions_result
          return r if r
        end
        nil
      end

      def clear_code_actions_result
        @clients.each_value { |c| c.last_code_actions_result = nil }
      end

      # Send workspace/executeCommand. Returns true on dispatch.
      def request_execute_command(buffer, command, arguments = nil)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.execute_command(command, arguments)
        true
      end

      # Send codeAction/resolve for an unresolved CodeAction. Returns
      # true when the request was dispatched.
      def request_code_action_resolve(buffer, action)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.code_action_resolve(action)
        true
      end

      def last_code_action_resolve_result
        @clients.each_value do |c|
          r = c.last_code_action_resolve_result
          return r if r
        end
        nil
      end

      def clear_code_action_resolve_result
        @clients.each_value { |c| c.last_code_action_resolve_result = nil }
      end

      # Send textDocument/inlayHint for the whole buffer. Result
      # (InlayHint[] | null) is cached server-side; once it lands we
      # bucket the hints by line via #inlay_hints_by_line so the
      # renderer can look them up O(1) per row.
      def request_inlay_hints(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        line_count = buffer.lines.size
        range = {
          start: { line: 0, character: 0 },
          end:   { line: [line_count, 0].max, character: 0 },
        }
        client.inlay_hint(buffer_uri(buffer), range)
        @last_hints_pulled_at[buffer.id] = monotonic_now
        true
      end

      # Throttled auto-pull called from the render loop. Cheap when
      # the interval hasn't elapsed; sends a fresh inlayHint request
      # otherwise. The response lands asynchronously and is bucketed
      # into @inlay_hints_cache once the editor pumps responses.
      def maybe_pull_inlay_hints(buffer)
        return false unless buffer

        last = @last_hints_pulled_at[buffer.id]
        return false if last && monotonic_now - last < HINTS_PULL_INTERVAL

        request_inlay_hints(buffer)
      end

      def last_inlay_hints_result
        @clients.each_value do |c|
          r = c.last_inlay_hints_result
          return r if r
        end
        nil
      end

      def clear_inlay_hints_result
        @clients.each_value { |c| c.last_inlay_hints_result = nil }
      end

      # Bucket the cached hints by 0-based line number. Each line's
      # entry is an array of hint hashes sorted by character position.
      # The renderer calls this once per render_window pass.
      def inlay_hints_by_line(buffer)
        return {} unless buffer

        # Drain a freshly-arrived result into the per-buffer cache.
        result = last_inlay_hints_result
        if result.is_a?(Array)
          @inlay_hints_cache[buffer.id] = result
          clear_inlay_hints_result
        end

        out = Hash.new { |h, k| h[k] = [] }
        (@inlay_hints_cache[buffer.id] || []).each do |hint|
          line = hint.dig(:position, :line)
          next unless line

          out[line.to_i] << hint
        end
        out.each_value { |arr| arr.sort_by! { |h| h.dig(:position, :character).to_i } }
        out
      end

      # Send textDocument/completion at the cursor position. Result
      # (CompletionItem[] | CompletionList | null) lands on the client.
      def request_completion(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        client.completion(buffer_uri(buffer),
                          @editor.line_index, @editor.byte_pointer)
        true
      end

      def last_completion_result
        @clients.each_value do |c|
          r = c.last_completion_result
          return r if r
        end
        nil
      end

      def clear_completion_result
        @clients.each_value { |c| c.last_completion_result = nil }
      end

      # Does the active client advertise codeActionProvider.resolveProvider?
      # When true, code actions returned without `edit`/`command` need to
      # be resolved via codeAction/resolve before they can be applied.
      def code_action_resolve_required?(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client

        provider = client.capabilities&.dig(:codeActionProvider)
        provider.is_a?(Hash) && provider[:resolveProvider] == true
      end

      # Does the active client for this buffer's filetype advertise
      # renameProvider.prepareProvider: true? If so, the rename flow
      # must call prepareRename first.
      def rename_prepare_required?(buffer)
        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client

        provider = client.capabilities&.dig(:renameProvider)
        provider.is_a?(Hash) && provider[:prepareProvider] == true
      end

      def last_rename_result
        @clients.each_value do |c|
          r = c.last_rename_result
          return r if r
        end
        nil
      end

      def clear_rename_result
        @clients.each_value { |c| c.last_rename_result = nil }
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

      # Force-flush any unsynced buffer state via didChange, bypassing the
      # CHANGE_DEBOUNCE_INTERVAL gate. Called before LSP requests that
      # depend on the server having an up-to-date document (rename,
      # definition, hover, etc.) so a rapid burst of edits followed by a
      # command can't leave the server one or two characters behind.
      def flush_changes(buffer)
        return false unless buffer

        ft = filetype_for(buffer)
        client = @clients[ft]
        return false unless client && client.status == :running

        fp = buffer.lines.hash
        return false if @synced_fingerprints[buffer.id] == fp

        did_change(buffer)
        @synced_fingerprints[buffer.id] = fp
        @synced_at[buffer.id] = monotonic_now
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

      # Is any client still waiting on a reply to a `method_name` request?
      # The editor's sync-poll helpers use this to detect that the server
      # has answered (even with `null`) and stop waiting early.
      def pending_for?(method_name)
        @clients.each_value.any? { |c| c.respond_to?(:pending_for?) && c.pending_for?(method_name) }
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
