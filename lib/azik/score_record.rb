require 'time'

module Azik
  ScoreRecord = Struct.new(
    :timestamp,
    :mode,
    :raw_kpm,
    :effective_kpm,
    :accuracy,
    :total_keystrokes,
    :miss_count,
    :elapsed_ms,
    keyword_init: true
  ) do
    def to_h
      {
        timestamp: timestamp.iso8601,
        mode: mode.to_s,
        raw_kpm: raw_kpm,
        effective_kpm: effective_kpm,
        accuracy: accuracy,
        total_keystrokes: total_keystrokes,
        miss_count: miss_count,
        elapsed_ms: elapsed_ms
      }
    end

    def self.from_hash(h)
      sym = h.transform_keys(&:to_sym)
      new(
        timestamp: Time.iso8601(sym[:timestamp]),
        mode: sym[:mode].to_sym,
        raw_kpm: sym[:raw_kpm].to_f,
        effective_kpm: sym[:effective_kpm].to_f,
        accuracy: sym[:accuracy].to_f,
        total_keystrokes: sym[:total_keystrokes].to_i,
        miss_count: sym[:miss_count].to_i,
        elapsed_ms: sym[:elapsed_ms].to_i
      )
    end
  end
end
