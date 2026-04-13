# frozen_string_literal: true

require 'open3'

module Rvim
  class Filter
    Result = Struct.new(:stdout, :stderr, :status, keyword_init: true) do
      def success?
        status.success?
      end
    end

    def self.run(cmd, input: '', shell: '/bin/sh', shellcmdflag: '-c')
      sh = shell.to_s.empty? ? '/bin/sh' : shell
      flag = shellcmdflag.to_s.empty? ? '-c' : shellcmdflag
      out, err, status = Open3.capture3(sh, flag, cmd.to_s, stdin_data: input.to_s)
      Result.new(stdout: out, stderr: err, status: status)
    rescue => e
      Result.new(stdout: '', stderr: e.message, status: failed_status)
    end

    def self.failed_status
      Struct.new(:success?, :exitstatus).new(false, 1)
    end
  end
end
