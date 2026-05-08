module Azik
  class Metrics
    attr_reader :total_keystrokes, :miss_count, :elapsed_ms

    def initialize(total_keystrokes:, miss_count:, elapsed_ms:)
      @total_keystrokes = total_keystrokes
      @miss_count = miss_count
      @elapsed_ms = elapsed_ms
    end

    def kpm
      return 0.0 if elapsed_ms.zero?
      total_keystrokes.to_f / (elapsed_ms / 60_000.0)
    end

    def accuracy
      return 1.0 if total_keystrokes.zero?
      1.0 - miss_count.to_f / total_keystrokes
    end

    def effective_kpm
      kpm * accuracy
    end
  end

  class MetricsAccumulator
    def initialize
      @cum_keys = 0
      @cum_miss = 0
      @cur_keys = 0
      @cur_miss = 0
      @elapsed_ms = 0
    end

    def update(total_keystrokes:, miss_count:, elapsed_ms:)
      @cur_keys = total_keystrokes
      @cur_miss = miss_count
      @elapsed_ms = elapsed_ms
    end

    def commit
      @cum_keys += @cur_keys
      @cum_miss += @cur_miss
      @cur_keys = 0
      @cur_miss = 0
    end

    def reset
      @cum_keys = @cum_miss = @cur_keys = @cur_miss = @elapsed_ms = 0
    end

    def current
      Metrics.new(
        total_keystrokes: @cum_keys + @cur_keys,
        miss_count: @cum_miss + @cur_miss,
        elapsed_ms: @elapsed_ms
      )
    end
  end
end
