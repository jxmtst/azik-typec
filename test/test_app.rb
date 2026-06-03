require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'time'
require_relative '../lib/azik/app'

class TestApp < Minitest::Test
  def make_record(time_str, eff)
    Azik::ScoreRecord.new(
      timestamp: Time.iso8601(time_str), mode: :sentence,
      raw_kpm: eff + 10, effective_kpm: eff, accuracy: 0.95,
      total_keystrokes: 300, miss_count: 15, elapsed_ms: 60_000
    )
  end

  def test_past_today_records_excludes_current_and_other_dates
    original = ENV['XDG_DATA_HOME']
    Dir.mktmpdir do |dir|
      ENV['XDG_DATA_HOME'] = dir
      app = Azik::App.new

      store = Azik::ScoreStore.new(path: Azik::ScoreStore.default_path)
      current   = make_record('2026-05-12T12:00:00+09:00', 250.0)
      past_today = make_record('2026-05-12T09:00:00+09:00', 300.0)
      yesterday  = make_record('2026-05-11T09:00:00+09:00', 400.0)
      store.append(current)
      store.append(past_today)
      store.append(yesterday)

      all_records = store.load_all
      result = app.past_today_records(current, all_records)
      assert_equal [300.0], result.map(&:effective_kpm)
    end
  ensure
    ENV['XDG_DATA_HOME'] = original
  end

  def test_build_score_record_truncates_subseconds
    original = ENV['XDG_DATA_HOME']
    Dir.mktmpdir do |dir|
      ENV['XDG_DATA_HOME'] = dir
      app = Azik::App.new
      metrics = Azik::Metrics.new(total_keystrokes: 100, miss_count: 5, elapsed_ms: 60_000)
      now = Time.at(1_700_000_000.5)
      record = app.build_score_record(metrics, now)
      assert_equal 1_700_000_000, record.timestamp.to_i
      assert_equal 0, record.timestamp.subsec
    end
  ensure
    ENV['XDG_DATA_HOME'] = original
  end

  def test_render_score_board_includes_current_record_in_daily_chart
    original = ENV['XDG_DATA_HOME']
    Dir.mktmpdir do |dir|
      ENV['XDG_DATA_HOME'] = dir
      app = Azik::App.new

      current = make_record('2026-05-12T12:00:00+09:00', 250.0)
      store = Azik::ScoreStore.new(path: Azik::ScoreStore.default_path)
      store.append(current)

      out, _err = capture_io { app.render_score_board(current) }
      today_line = out.lines.find { |l| l.include?('2026-05-12') }
      refute_nil today_line, '今日の行がチャートに存在すべき'
      assert_match(/250\.0/, today_line, '今日の行に今回のKPMが表示されるべき')
      refute_match(/2026-05-12.* - /, today_line, '今日の行が "-" になっていないこと')
    end
  ensure
    ENV['XDG_DATA_HOME'] = original
  end
end
