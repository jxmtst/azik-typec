require 'minitest/autorun'
require 'date'
require 'time'
require 'azik/score_record'
require 'azik/score_board'

class TestScoreBoardAggregation < Minitest::Test
  def rec(time_str, eff)
    Azik::ScoreRecord.new(
      timestamp: Time.iso8601(time_str), mode: :sentence,
      raw_kpm: eff + 10, effective_kpm: eff, accuracy: 0.95,
      total_keystrokes: 300, miss_count: 15, elapsed_ms: 60_000
    )
  end

  def now
    Time.iso8601('2026-05-12T12:00:00+09:00')
  end

  def test_top_of_day_includes_today_only
    records = [
      rec('2026-05-11T23:59:59+09:00', 100.0),
      rec('2026-05-12T00:00:01+09:00', 200.0),
      rec('2026-05-12T10:00:00+09:00', 300.0),
      rec('2026-05-13T00:00:01+09:00', 400.0)
    ]
    board = Azik::ScoreBoard.new(records: records, now: now)
    tops = board.top_of_day(limit: 5)
    effs = tops.map(&:effective_kpm)
    assert_equal [300.0, 200.0], effs
  end

  def test_top_of_day_limits_to_n
    records = (1..10).map { |i| rec('2026-05-12T10:00:00+09:00', i * 10.0) }
    board = Azik::ScoreBoard.new(records: records, now: now)
    tops = board.top_of_day(limit: 5)
    assert_equal 5, tops.size
    assert_equal [100.0, 90.0, 80.0, 70.0, 60.0], tops.map(&:effective_kpm)
  end

  def test_daily_bests_returns_14_entries_oldest_first
    records = [
      rec('2026-05-12T10:00:00+09:00', 300.0),
      rec('2026-05-12T11:00:00+09:00', 350.0),
      rec('2026-05-10T10:00:00+09:00', 200.0)
    ]
    board = Azik::ScoreBoard.new(records: records, now: now)
    daily = board.daily_bests(days: 14)
    assert_equal 14, daily.size
    assert_equal Date.new(2026, 4, 29), daily.first[:date]
    assert_equal Date.new(2026, 5, 12), daily.last[:date]
    assert_in_delta 350.0, daily.last[:best], 0.001
    assert_in_delta 200.0, daily[11][:best], 0.001  # 5/10
    assert_nil daily[12][:best]  # 5/11
  end
end
