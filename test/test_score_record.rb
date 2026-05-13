require 'minitest/autorun'
require 'time'
require 'azik/score_record'

class TestScoreRecord < Minitest::Test
  def sample
    Azik::ScoreRecord.new(
      timestamp: Time.iso8601('2026-05-12T14:23:01+09:00'),
      mode: :sentence,
      raw_kpm: 312.4,
      effective_kpm: 298.1,
      accuracy: 0.954,
      total_keystrokes: 312,
      miss_count: 15,
      elapsed_ms: 60_000
    )
  end

  def test_to_h_serializes_timestamp_as_iso8601
    h = sample.to_h
    assert_equal '2026-05-12T14:23:01+09:00', h[:timestamp]
    assert_equal 'sentence', h[:mode]
    assert_in_delta 298.1, h[:effective_kpm], 0.001
  end

  def test_roundtrip_via_from_hash
    h = sample.to_h
    r = Azik::ScoreRecord.from_hash(h)
    assert_equal sample.timestamp.to_i, r.timestamp.to_i
    assert_equal :sentence, r.mode
    assert_in_delta sample.effective_kpm, r.effective_kpm, 0.001
    assert_equal sample.total_keystrokes, r.total_keystrokes
  end

  def test_from_hash_accepts_string_keys
    h = sample.to_h.transform_keys(&:to_s)
    r = Azik::ScoreRecord.from_hash(h)
    assert_equal :sentence, r.mode
  end
end
