# frozen_string_literal: true

module Rvim
  module Diff
    # Compute per-line diff statuses for a vs b. Returns [a_status, b_status],
    # each an array same length as its source where each entry is :common or
    # :differs. Common lines are those that participate in the longest common
    # subsequence between the two; everything else is marked :differs.
    def self.compute(a, b)
      a_status = Array.new(a.size, :differs)
      b_status = Array.new(b.size, :differs)
      lcs(a, b).each do |(i, j)|
        a_status[i] = :common
        b_status[j] = :common
      end
      [a_status, b_status]
    end

    def self.lcs(a, b)
      m = a.size
      n = b.size
      return [] if m.zero? || n.zero?

      dp = Array.new(m + 1) { Array.new(n + 1, 0) }
      (1..m).each do |i|
        (1..n).each do |j|
          dp[i][j] = if a[i - 1] == b[j - 1]
                       dp[i - 1][j - 1] + 1
                     else
                       [dp[i - 1][j], dp[i][j - 1]].max
                     end
        end
      end

      pairs = []
      i = m
      j = n
      while i > 0 && j > 0
        if a[i - 1] == b[j - 1]
          pairs.unshift([i - 1, j - 1])
          i -= 1
          j -= 1
        elsif dp[i - 1][j] >= dp[i][j - 1]
          i -= 1
        else
          j -= 1
        end
      end
      pairs
    end

    # Returns an array of hunk start indices in the given status array. A hunk
    # starts at any :differs line that is preceded by :common (or at index 0
    # if the buffer starts with a differing line).
    def self.hunk_starts(status)
      starts = []
      status.each_with_index do |s, i|
        next unless s == :differs
        next if i.positive? && status[i - 1] == :differs

        starts << i
      end
      starts
    end
  end
end
