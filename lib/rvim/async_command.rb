# frozen_string_literal: true

require 'open3'
require 'thread'

module Rvim
  # A long-running subprocess whose stdout/stderr is streamed
  # line-by-line into a thread-safe queue. The main editor loop polls
  # via #drain instead of blocking on the pipe.
  #
  # Used by :LspCodeLens N (test runs) so the editor stays responsive
  # while tests execute; the buffer auto-updates as output arrives.
  class AsyncCommand
    attr_reader :cmd

    def initialize(cmd, shell:, shellcmdflag:)
      @cmd = cmd
      @shell = shell
      @shellcmdflag = shellcmdflag
      @queue = Thread::Queue.new
      @reader_done = false
      @exit_status = nil
    end

    # Spawn the subprocess and start the reader thread. Combines
    # stdout + stderr so output ordering matches what the user would
    # see on a real terminal.
    def start
      argv = [@shell, @shellcmdflag, @cmd]
      stdin, output, @wait_thread = Open3.popen2e(*argv)
      stdin.close
      @reader = Thread.new do
        output.each_line do |line|
          @queue << line.chomp
        end
        @exit_status = @wait_thread.value.exitstatus
        @reader_done = true
      end
    end

    # Pop all currently-available lines without blocking. Returns
    # Array<String> (empty when nothing new has arrived since the
    # last drain).
    def drain
      lines = []
      lines << @queue.pop(true) until @queue.empty?
      lines
    rescue ThreadError
      lines
    end

    # True when the subprocess has exited AND every emitted line has
    # been drained — callers safely finalize after this turns true.
    def done?
      @reader_done && @queue.empty?
    end

    def exit_status
      @exit_status
    end
  end
end
