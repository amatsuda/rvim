# frozen_string_literal: true

require_relative 'job'

module Rvim
  # Thin facade over Rvim::Job preserving the simpler API used by
  # :LspCodeLens and :LspWatch — `start` / `drain` returning a flat
  # Array<String> of combined stdout+stderr lines / `done?` /
  # `exit_status`.
  #
  # The richer Job API (separate streams, stdin pipe, kill signals)
  # is exposed to Lua via vim.fn.jobstart in lib/rvim/lua/job.rb.
  class AsyncCommand
    attr_reader :cmd

    def initialize(cmd, shell:, shellcmdflag:)
      @cmd = cmd
      @job = Rvim::Job.new(cmd, shell: shell, shellcmdflag: shellcmdflag)
    end

    def start
      @job.start
    end

    # Pop newly-available lines from either stream as a flat
    # Array<String>, matching the previous popen2e behavior — the
    # callers (terminal buffers) don't care about ordering between
    # streams beyond best-effort.
    def drain
      lines = []
      @job.drain.each do |stream, payload|
        next unless %i[stdout stderr].include?(stream)

        lines << payload
      end
      lines
    end

    def done?
      @job.done?
    end

    def exit_status
      @job.exit_status
    end
  end
end
