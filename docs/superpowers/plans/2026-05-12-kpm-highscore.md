# KPMハイスコア記録・表示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Session:** `3f48d176-ab86-4ab1-9567-eac871a628b4` (`claude --resume 3f48d176-ab86-4ab1-9567-eac871a628b4` で会話を再開)

**Spec:** `docs/superpowers/specs/2026-05-12-kpm-highscore-design.md`

**Goal:** 文章モードの制限時間超過時にKPMをJSONLに保存し、当日TOP5と過去14日の日次ベスト棒グラフを表示する。

**Architecture:** 3層分離 — `ScoreRecord`（値オブジェクト）／`ScoreStore`（JSONL I/O）／`ScoreBoard`（集計＋描画）。各ユニットを独立にテスト可能にし、`bin/az` の `run` ループに最小限のフックを差し込む。

**Tech Stack:** Ruby（標準ライブラリのみ追加 — `json` / `fileutils` / `time` / `date`）。テストは既存のminitest。

---

## File Structure

新規作成:
- `lib/azik/score_record.rb` — 値オブジェクト（Struct）。`to_h` / `from_hash` でJSON相互変換。
- `lib/azik/score_store.rb` — JSONL append / load。壊れた行をスキップ。`default_path` でXDG解決。
- `lib/azik/score_board.rb` — 集計（`top_of_day` / `daily_bests`）＋描画（`render_current` / `render_top_of_day` / `render_daily_chart`）。
- `test/test_score_record.rb`
- `test/test_score_store.rb`
- `test/test_score_board.rb`

変更:
- `bin/az` — `require` 追加、`@store` 初期化、`time_up?` ブランチで保存＆スコア画面描画。
- `test/test_smoke.rb` — `XDG_DATA_HOME` を一時ディレクトリに切替えてユーザー環境を汚さないようにする。

---

## Task 1: ScoreRecord 値オブジェクト

**Files:**
- Create: `lib/azik/score_record.rb`
- Test: `test/test_score_record.rb`

- [ ] **Step 1: Write the failing test**

`test/test_score_record.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/test_score_record.rb`

Expected: LoadError — `azik/score_record` not found。

- [ ] **Step 3: Write minimal implementation**

`lib/azik/score_record.rb`:

```ruby
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Ilib -Itest test/test_score_record.rb`

Expected: 3 runs, 3 assertions, 0 failures。

- [ ] **Step 5: Commit**

```bash
git add lib/azik/score_record.rb test/test_score_record.rb
git commit -m "feat: add ScoreRecord value object"
```

---

## Task 2: ScoreStore — append/load_all

**Files:**
- Create: `lib/azik/score_store.rb`
- Test: `test/test_score_store.rb`

- [ ] **Step 1: Write the failing tests**

`test/test_score_store.rb`:

```ruby
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'time'
require 'azik/score_record'
require 'azik/score_store'

class TestScoreStore < Minitest::Test
  def sample(t = Time.iso8601('2026-05-12T14:23:01+09:00'), eff: 298.1)
    Azik::ScoreRecord.new(
      timestamp: t, mode: :sentence,
      raw_kpm: 312.4, effective_kpm: eff, accuracy: 0.954,
      total_keystrokes: 312, miss_count: 15, elapsed_ms: 60_000
    )
  end

  def test_append_then_load_roundtrip
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'scores.jsonl')
      store = Azik::ScoreStore.new(path: path)
      store.append(sample)
      records = store.load_all
      assert_equal 1, records.size
      assert_in_delta 298.1, records.first.effective_kpm, 0.001
    end
  end

  def test_append_creates_parent_directory
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'a', 'b', 'scores.jsonl')
      store = Azik::ScoreStore.new(path: path)
      store.append(sample)
      assert File.exist?(path)
    end
  end

  def test_load_all_returns_empty_when_file_missing
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'absent.jsonl')
      store = Azik::ScoreStore.new(path: path)
      assert_equal [], store.load_all
    end
  end

  def test_load_all_skips_broken_lines
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'scores.jsonl')
      store = Azik::ScoreStore.new(path: path)
      store.append(sample(eff: 100.0))
      File.open(path, 'a') { |f| f.puts 'not-json' }
      File.open(path, 'a') { |f| f.puts '{"timestamp":"2026-05-12T14:23:01+09:00"}' } # missing keys
      store.append(sample(eff: 200.0))
      records = store.load_all
      assert_equal 2, records.size
      kpms = records.map(&:effective_kpm).sort
      assert_in_delta 100.0, kpms[0], 0.001
      assert_in_delta 200.0, kpms[1], 0.001
    end
  end

  def test_default_path_uses_xdg_data_home_when_set
    Dir.mktmpdir do |dir|
      ENV['XDG_DATA_HOME'] = dir
      path = Azik::ScoreStore.default_path
      assert_equal File.join(dir, 'azik-typec', 'scores.jsonl'), path
    ensure
      ENV.delete('XDG_DATA_HOME')
    end
  end

  def test_default_path_falls_back_to_local_share
    ENV.delete('XDG_DATA_HOME')
    path = Azik::ScoreStore.default_path
    assert path.end_with?(File.join('.local', 'share', 'azik-typec', 'scores.jsonl'))
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Ilib -Itest test/test_score_store.rb`

Expected: LoadError — `azik/score_store` not found。

- [ ] **Step 3: Write minimal implementation**

`lib/azik/score_store.rb`:

```ruby
require 'json'
require 'fileutils'
require 'azik/score_record'

module Azik
  class ScoreStore
    REQUIRED_KEYS = %w[timestamp mode raw_kpm effective_kpm accuracy total_keystrokes miss_count elapsed_ms].freeze

    def self.default_path
      base = ENV['XDG_DATA_HOME']
      base = File.join(Dir.home, '.local', 'share') if base.nil? || base.empty?
      File.join(base, 'azik-typec', 'scores.jsonl')
    end

    def initialize(path:)
      @path = path
    end

    attr_reader :path

    def append(record)
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, 'a') do |f|
        f.puts JSON.generate(record.to_h)
      end
    end

    def load_all
      return [] unless File.exist?(@path)
      records = []
      File.foreach(@path) do |line|
        line = line.strip
        next if line.empty?
        begin
          hash = JSON.parse(line)
        rescue JSON::ParserError
          next
        end
        next unless REQUIRED_KEYS.all? { |k| hash.key?(k) }
        begin
          records << ScoreRecord.from_hash(hash)
        rescue ArgumentError, TypeError
          next
        end
      end
      records
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Ilib -Itest test/test_score_store.rb`

Expected: 6 runs, 0 failures。

- [ ] **Step 5: Commit**

```bash
git add lib/azik/score_store.rb test/test_score_store.rb
git commit -m "feat: add ScoreStore for JSONL persistence"
```

---

## Task 3: ScoreBoard — 集計API

**Files:**
- Create: `lib/azik/score_board.rb` (集計部分のみ。描画は次タスクで追加)
- Test: `test/test_score_board.rb`

- [ ] **Step 1: Write the failing tests**

`test/test_score_board.rb`:

```ruby
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
      rec('2026-05-11T23:59:59+09:00', 100.0),   # 前日
      rec('2026-05-12T00:00:01+09:00', 200.0),   # 当日
      rec('2026-05-12T10:00:00+09:00', 300.0),   # 当日
      rec('2026-05-13T00:00:01+09:00', 400.0)    # 翌日（理論上未来だがテスト用）
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
      rec('2026-05-12T11:00:00+09:00', 350.0),  # 同日でこちらが最高
      rec('2026-05-10T10:00:00+09:00', 200.0)
    ]
    board = Azik::ScoreBoard.new(records: records, now: now)
    daily = board.daily_bests(days: 14)
    assert_equal 14, daily.size
    assert_equal Date.new(2026, 4, 29), daily.first[:date]
    assert_equal Date.new(2026, 5, 12), daily.last[:date]
    assert_in_delta 350.0, daily.last[:best], 0.001
    assert_in_delta 200.0, daily[11][:best], 0.001  # 5/10
    assert_nil daily[12][:best]  # 5/11 は記録なし
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Ilib -Itest test/test_score_board.rb`

Expected: LoadError — `azik/score_board` not found。

- [ ] **Step 3: Write minimal implementation**

`lib/azik/score_board.rb`:

```ruby
require 'date'

module Azik
  class ScoreBoard
    def initialize(records:, now:)
      @records = records
      @now = now
      @today = now.to_date
    end

    def top_of_day(limit: 5)
      today_records.sort_by { |r| -r.effective_kpm }.first(limit)
    end

    def daily_bests(days: 14)
      start_date = @today - (days - 1)
      by_date = today_records_window(start_date).group_by { |r| r.timestamp.to_date }
      (0...days).map do |offset|
        d = start_date + offset
        best = by_date[d]&.map(&:effective_kpm)&.max
        { date: d, best: best }
      end
    end

    private

    def today_records
      @records.select { |r| r.timestamp.to_date == @today }
    end

    def today_records_window(start_date)
      @records.select { |r| (start_date..@today).cover?(r.timestamp.to_date) }
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Ilib -Itest test/test_score_board.rb`

Expected: 3 runs, 0 failures。

- [ ] **Step 5: Commit**

```bash
git add lib/azik/score_board.rb test/test_score_board.rb
git commit -m "feat: add ScoreBoard aggregation (top_of_day, daily_bests)"
```

---

## Task 4: ScoreBoard — 描画API

**Files:**
- Modify: `lib/azik/score_board.rb`
- Modify: `test/test_score_board.rb`

- [ ] **Step 1: Add failing rendering tests**

`test/test_score_board.rb` の末尾に追加:

```ruby
class TestScoreBoardRendering < Minitest::Test
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

  def test_render_current_contains_kpm_values
    board = Azik::ScoreBoard.new(records: [], now: now)
    r = rec('2026-05-12T12:00:00+09:00', 298.1)
    out = board.render_current(r)
    assert_match(/298\.1/, out)
    assert_match(/308\.1/, out)   # raw_kpm
    assert_match(/95\.0%/, out)   # accuracy
  end

  def test_render_top_of_day_lists_rankings
    today_records = [
      rec('2026-05-12T08:00:00+09:00', 300.0),
      rec('2026-05-12T09:00:00+09:00', 250.0)
    ]
    board = Azik::ScoreBoard.new(records: today_records, now: now)
    out = board.render_top_of_day(today_records)
    assert_match(/1\..*300\.0/, out)
    assert_match(/2\..*250\.0/, out)
  end

  def test_render_top_of_day_shows_placeholder_when_empty
    board = Azik::ScoreBoard.new(records: [], now: now)
    out = board.render_top_of_day([])
    assert_match(/記録なし/, out)
  end

  def test_render_daily_chart_highlights_today_and_shows_dash_for_missing
    daily = [
      { date: Date.new(2026, 5, 10), best: 200.0 },
      { date: Date.new(2026, 5, 11), best: nil },
      { date: Date.new(2026, 5, 12), best: 300.0 }
    ]
    board = Azik::ScoreBoard.new(records: [], now: now)
    out = board.render_daily_chart(daily)
    assert_match(/2026-05-12/, out)
    assert_match(/300\.0/, out)
    assert_match(/2026-05-11.* - /, out)  # missing → " - "
    assert_match(/←/, out)                 # 今日マーカー
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Ilib -Itest test/test_score_board.rb`

Expected: NoMethodError — `render_current` 等が未定義。

- [ ] **Step 3: Add rendering methods**

`lib/azik/score_board.rb` を以下で置き換え（既存の集計部分も保持）:

```ruby
require 'date'

module Azik
  class ScoreBoard
    CHART_WIDTH = 40
    FULL = '█'
    HALF = '▌'
    EMPTY_DAY = '·'
    CSI = "\e["
    DIM = "#{CSI}90m"
    BOLD_CYAN = "#{CSI}1;36m"
    RESET = "#{CSI}0m"

    def initialize(records:, now:)
      @records = records
      @now = now
      @today = now.to_date
    end

    def top_of_day(limit: 5)
      today_records.sort_by { |r| -r.effective_kpm }.first(limit)
    end

    def daily_bests(days: 14)
      start_date = @today - (days - 1)
      by_date = today_records_window(start_date).group_by { |r| r.timestamp.to_date }
      (0...days).map do |offset|
        d = start_date + offset
        best = by_date[d]&.map(&:effective_kpm)&.max
        { date: d, best: best }
      end
    end

    def render_current(record)
      format(
        "今回: 実効 %.1f KPM / 生 %.1f KPM / 正解率 %.1f%% / 打鍵 %d / miss %d\n",
        record.effective_kpm,
        record.raw_kpm,
        record.accuracy * 100,
        record.total_keystrokes,
        record.miss_count
      )
    end

    def render_top_of_day(records)
      lines = ["[当日TOP5（過去分）]"]
      if records.empty?
        lines << "  記録なし"
      else
        records.first(5).each_with_index do |r, i|
          lines << format(
            "  %d. %s  %.1f KPM (acc %.1f%%)",
            i + 1,
            r.timestamp.strftime('%H:%M'),
            r.effective_kpm,
            r.accuracy * 100
          )
        end
      end
      lines.join("\n") + "\n"
    end

    def render_daily_chart(daily)
      max_best = daily.map { |d| d[:best] || 0 }.max
      max_best = 1 if max_best.zero?
      lines = ["[過去14日 日次ベスト]"]
      daily.each do |entry|
        date_str = entry[:date].strftime('%Y-%m-%d')
        is_today = entry[:date] == @today
        bar = bar_for(entry[:best], max_best)
        value = entry[:best] ? format('%.1f KPM', entry[:best]) : ' - '
        line = format('  %s  %-*s  %s', date_str, CHART_WIDTH, bar, value)
        line = "#{BOLD_CYAN}#{line} ←#{RESET}" if is_today
        lines << line
      end
      lines.join("\n") + "\n"
    end

    private

    def today_records
      @records.select { |r| r.timestamp.to_date == @today }
    end

    def today_records_window(start_date)
      @records.select { |r| (start_date..@today).cover?(r.timestamp.to_date) }
    end

    def bar_for(best, max_best)
      return EMPTY_DAY * 2 if best.nil?
      ratio = [best.to_f / max_best, 1.0].min
      cells = ratio * CHART_WIDTH
      full = cells.floor
      half = (cells - full) >= 0.5 ? 1 : 0
      (FULL * full) + (HALF * half)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Ilib -Itest test/test_score_board.rb`

Expected: 7 runs (3 aggregation + 4 rendering), 0 failures。

- [ ] **Step 5: Commit**

```bash
git add lib/azik/score_board.rb test/test_score_board.rb
git commit -m "feat: add ScoreBoard rendering (current/top/chart)"
```

---

## Task 5: bin/az — スコア保存・描画フック

**Files:**
- Modify: `bin/az`
- Modify: `test/test_smoke.rb`

- [ ] **Step 1: Guard test_smoke.rb against XDG side-effects**

`test/test_smoke.rb` の `require` 群の直後に以下を追加:

```ruby
require 'tmpdir'
ENV['XDG_DATA_HOME'] = Dir.mktmpdir('azik-test-')
```

これで `bin/az` が読み込まれてもユーザーのscoresファイルを汚さない。

- [ ] **Step 2: Run smoke test to confirm still green**

Run: `bundle exec rake test TEST=test/test_smoke.rb`

Expected: 全テストpass。

- [ ] **Step 3: Modify bin/az — add requires and store**

`bin/az` の `require` ブロックに追加:

```ruby
require 'azik/score_record'
require 'azik/score_store'
require 'azik/score_board'
```

`App#initialize` の末尾（`new_session` 呼び出し前）に追加:

```ruby
@store = ScoreStore.new(path: ScoreStore.default_path)
```

差し替え後の `initialize`:

```ruby
def initialize
  @entries = Entries.load
  @decomposer = Decomposer.new(@entries)
  @mode = :sentence
  @acc = MetricsAccumulator.new
  @store = ScoreStore.new(path: ScoreStore.default_path)
  new_session
end
```

- [ ] **Step 4: Add helper methods to App**

`bin/az` の `App` クラス内に以下のメソッドを追加（`run` の直前に配置）:

```ruby
def build_score_record(metrics, now)
  ScoreRecord.new(
    timestamp: now,
    mode: :sentence,
    raw_kpm: metrics.kpm,
    effective_kpm: metrics.effective_kpm,
    accuracy: metrics.accuracy,
    total_keystrokes: metrics.total_keystrokes,
    miss_count: metrics.miss_count,
    elapsed_ms: metrics.elapsed_ms
  )
end

def render_score_board(current_record)
  now = current_record.timestamp
  past_records = @store.load_all.reject { |r| r.timestamp == current_record.timestamp }
  board = ScoreBoard.new(records: past_records, now: now)
  today_past = past_records.select { |r| r.timestamp.to_date == now.to_date }
  TUI.clear_screen
  TUI.move(1, 1)
  puts "=== AZIK Type [スコア] ===\r"
  puts "\r"
  puts board.render_current(current_record).gsub("\n", "\r\n")
  puts "\r"
  puts board.render_top_of_day(today_past.sort_by { |r| -r.effective_kpm }).gsub("\n", "\r\n")
  puts "\r"
  puts board.render_daily_chart(board.daily_bests(days: 14)).gsub("\n", "\r\n")
end
```

- [ ] **Step 5: Hook into run loop**

`bin/az` の `run` メソッド内、`if time_up? || @finished` ブロックを以下で置き換え:

```ruby
if time_up? || @finished
  if @mode == :sentence && time_up?
    @acc.update(total_keystrokes: @matcher.total_keystrokes, miss_count: @matcher.miss_count, elapsed_ms: elapsed_ms)
    record = build_score_record(@acc.current, Time.now)
    @store.append(record)
    render_score_board(record)
  end
  puts "\r\n何かキーを押すと終了します。\r"
  io.getc
  break
end
```

- [ ] **Step 6: Run full test suite**

Run: `bundle exec rake test`

Expected: 全テストpass、副作用としてユーザーのscoresファイルが作成されないこと（`ls ~/.local/share/azik-typec` で確認）。

- [ ] **Step 7: Manual smoke run**

Run: `bin/az` を起動し、文章モードで60秒待ち（または `time_limit_sec` を一時的に短く設定して動作確認してもよい）、スコア画面が表示されることを確認。`~/.local/share/azik-typec/scores.jsonl` に1行追加されていることを確認。

```bash
ls -l ~/.local/share/azik-typec/scores.jsonl
tail -1 ~/.local/share/azik-typec/scores.jsonl
```

Expected: JSONLが1行記録されている。

- [ ] **Step 8: Commit**

```bash
git add bin/az test/test_smoke.rb
git commit -m "feat: persist KPM scores and render scoreboard after sentence mode"
```

---

## Task 6: README 更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add scoreboard section**

`README.md` の `## 構成` の上に以下のセクションを追加:

```markdown
## スコア記録

文章モードで制限時間を超過すると、KPM/正解率などを `~/.local/share/azik-typec/scores.jsonl`（`XDG_DATA_HOME` があればその配下）に追記し、終了直前に当日TOP5と過去14日の日次ベスト棒グラフを表示する。ドリル完了・ESC終了では記録しない。
```

`## 構成` のリストに以下を追加:

```markdown
- `lib/azik/score_record.rb` — スコアレコード値オブジェクト
- `lib/azik/score_store.rb` — JSONL 永続化
- `lib/azik/score_board.rb` — 集計・スコア画面描画
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document KPM scoreboard feature"
```

---

## Self-Review Summary

**Spec coverage:**
- 文章モード制限時間超過時の保存 → Task 5 Step 5
- 生KPM / 実効KPM 両方記録 → Task 1 (Struct fields) + Task 5 Step 4
- ESC・ドリルは保存しない → Task 5 Step 5 の条件 `@mode == :sentence && time_up?`
- 保存先 XDG準拠 → Task 2 (`default_path`)
- JSONL形式・壊れた行スキップ → Task 2 (`load_all` rescue + REQUIRED_KEYS チェック)
- ローカル日付で当日境界 → Task 3 (`@today = now.to_date`)
- 当日TOP5（今回除く） → Task 5 Step 4 (`reject { |r| r.timestamp == current_record.timestamp }`)
- 過去14日 日次ベスト棒グラフ → Task 3 + Task 4
- 今日の行強調 → Task 4 `BOLD_CYAN` + `←`
- 「何かキーを押すと終了」前にスコア画面 → Task 5 Step 5
- ユニットテスト3種 → Tasks 1/2/3/4
- スモークテストの XDG_DATA_HOME 差し替え → Task 5 Step 1

**Placeholder scan:** TBD・TODO・"appropriate error handling"・"similar to Task N" の使用なし。

**Type consistency:**
- `ScoreRecord` のフィールド名は全タスクで一致（`effective_kpm` / `raw_kpm` / `total_keystrokes` / `miss_count` / `elapsed_ms` / `mode` / `timestamp` / `accuracy`）。
- `ScoreBoard` API: `top_of_day(limit:)` / `daily_bests(days:)` / `render_current(record)` / `render_top_of_day(records)` / `render_daily_chart(daily)` で全タスク一致。
- `ScoreStore` API: `default_path` / `append(record)` / `load_all` で全タスク一致。
