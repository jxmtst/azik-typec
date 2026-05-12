# KPMハイスコア記録・表示 設計

**Session:** `3f48d176-ab86-4ab1-9567-eac871a628b4` (`claude --resume 3f48d176-ab86-4ab1-9567-eac871a628b4` で会話を再開)

## 背景・目的

`bin/az` の文章モードはセッション終了時にKPM/正解率を表示するだけで、結果が残らない。日々の上達を確認できるようにするため、文章モードのセッション結果を永続化し、終了時に当日TOP5と過去14日の日次ベストを可視化する。

## 要件

- 文章モードで制限時間を超過したときのみスコアを記録する（ESC終了・ドリル完了は対象外）
- 生KPM・実効KPMの両方を保存し、ランキングは実効KPMを主軸にする
- スコア画面は「何かキーを押すと終了」プロンプトの直前に挿入する
- 当日TOP5に**今回セッションは含めない**（今回は別表示、TOP5は過去分のみ）
- 過去14日（今日含む）の日次ベストを8ビット風横棒グラフで表示する
- 「当日」はローカル日付の `00:00`〜`23:59` で区切る
- 壊れたレコード（不正JSON・必須キー欠損）はスキップして継続する

## アーキテクチャ

責務を3層に分離し、各ユニットを独立にテスト可能にする。

```
lib/azik/
  score_record.rb   # 値オブジェクト
  score_store.rb    # JSONL I/O
  score_board.rb    # 集計 + 描画
bin/az              # time_up 時に保存・描画を呼ぶ
```

ファイル保存先: `XDG_DATA_HOME` があれば `$XDG_DATA_HOME/azik-typec/scores.jsonl`、無ければ `~/.local/share/azik-typec/scores.jsonl`

## データモデル

### ScoreRecord（値オブジェクト）

```ruby
ScoreRecord = Struct.new(
  :timestamp,        # Time（ローカル）
  :mode,             # :sentence のみ記録
  :raw_kpm,          # Float
  :effective_kpm,    # Float（ランキング主軸）
  :accuracy,         # Float (0..1)
  :total_keystrokes, # Integer
  :miss_count,       # Integer
  :elapsed_ms,       # Integer
  keyword_init: true
)
```

### JSONL 1行の例

```json
{"timestamp":"2026-05-12T14:23:01+09:00","mode":"sentence","raw_kpm":312.4,"effective_kpm":298.1,"accuracy":0.954,"total_keystrokes":312,"miss_count":15,"elapsed_ms":60000}
```

`mode` は将来のドリル対応に備えて保持する。今回の実装では `sentence` のみ書き込む。

## ユニット設計

### `Azik::ScoreStore`

JSONLの読み書きのみを担当する。集計・時刻判定は持たない。

```ruby
class ScoreStore
  def self.default_path                # XDG_DATA_HOME を解決した既定パス
  def initialize(path:)
  def append(record)                   # 親dir自動作成、追記オープン
  def load_all                         # 全レコード配列。壊れた行はskip。
end
```

- 書き込み: `FileUtils.mkdir_p` → `File.open(path, 'a')` → `JSON.generate(hash) + "\n"`
- 読み込み: `each_line` し、`JSON.parse` を `rescue JSON::ParserError` でスキップ
- 必須キー欠落の行も同様にスキップ
- timestamp は `Time.iso8601` でパース
- ファイル不存在時は空配列を返す
- 依存: `json`、`fileutils`、`time`（標準ライブラリのみ）

### `Azik::ScoreBoard`

`[ScoreRecord]` から集計と描画文字列の生成のみを行う。I/Oは持たない。

#### 集計API

```ruby
class ScoreBoard
  def initialize(records:, now:)             # now はTime（テスト容易性）

  # 当日0:00〜23:59のレコードを effective_kpm 降順で最大 limit 件
  def top_of_day(limit: 5)

  # 今日から過去14日（今日含む）の各日について effective_kpm 最高値を返す
  # 戻り値: [{ date: Date, best: Float | nil }, ...] 古い日付→新しい日付の順
  def daily_bests(days: 14)
end
```

#### 描画API

```ruby
class ScoreBoard
  def render_current(record)                 # 今回セッションの行（強調表示）
  def render_top_of_day(today_records)       # 当日TOP5
  def render_daily_chart(daily)              # 8ビット風横棒グラフ
end
```

#### グラフ仕様

- 1日1行、最大値を40カラム幅で正規化
- 記号は `█` 主・半端は `▌`、記録なしは `·`
- 今日の行は色強調
- イメージ:

```
2026-04-29  ████████████████████              298.1 KPM
2026-04-30  ··                                  -
2026-05-01  ██████████████████                275.3 KPM
…
2026-05-12  ████████████████████████████████  342.0 KPM ← 今日
```

### ScoreRecord と JSON 相互変換

`ScoreRecord` 自身に `#to_h`（JSON書き込み用、ISO8601文字列に変換）と `.from_hash`（読み込み用、ISO8601→Time）を持たせる。

## `bin/az` への組み込み

`require` を3つ追加し、初期化と `time_up` 時のフックを追加する。

```ruby
require 'azik/score_record'
require 'azik/score_store'
require 'azik/score_board'

# App#initialize 末尾
@store = ScoreStore.new(path: ScoreStore.default_path)
```

`time_up?` または `@finished` のブランチで、文章モード制限時間超過のときのみ保存→画面表示:

```ruby
if time_up? || @finished
  if @mode == :sentence && time_up?
    record = build_score_record   # 現在の @acc.current から組み立て
    @store.append(record)
    render_score_board(record)
  end
  puts "\r\n何かキーを押すと終了します。\r"
  io.getc
  break
end
```

- ドリル完了・ESC終了は保存・スコア画面ともにスキップ
- スコア画面は `TUI.clear_screen` 後に描画
- 当日TOP5は `load_all` 結果から「今回保存したレコードを除く」過去分のみ

## エラー処理

- JSONパース失敗・必須キー欠損: 該当行スキップ、他は処理継続
- ファイル不存在: 空配列扱い
- 書き込み失敗（権限など）は呼び出し側にraise（ユーザーが原因を見られる）

## テスト戦略

### `test/test_score_record.rb`
- 値オブジェクトの初期化と `to_h` / `from_hash` のラウンドトリップ

### `test/test_score_store.rb`（Tempfile利用）
- `append` → `load_all` のラウンドトリップ
- 壊れた行（不正JSON、必須キー欠損）を含むファイルでスキップ検証
- ファイル不存在時 `load_all == []`
- 親ディレクトリ未作成でも `append` が成功

### `test/test_score_board.rb`（now注入）
- 当日境界: 23:59 と翌日 00:01 のレコードが正しく分かれる
- `top_of_day` は effective_kpm 降順で上位N件
- `daily_bests` は14日分の配列を返す（記録ない日は `best: nil`）
- 描画系: 主要な要素（カラーコード、現在記録のハイライト、`-` / KPM値）が出力に含まれることをアサート

### スモークテスト
`test_smoke.rb` は `XDG_DATA_HOME` を一時ディレクトリに差し替えて、テスト副作用としてユーザー環境のscores.jsonlを汚さないようにする。

## 受け入れ条件

- 文章モードで制限時間を超過すると `~/.local/share/azik-typec/scores.jsonl`（または `XDG_DATA_HOME` 配下）に1行追加される
- スコア画面で以下が表示される:
  - 今回セッションの 実効KPM/生KPM/正解率/打鍵数/ミス
  - 当日の過去分TOP5（実効KPM降順、空なら「記録なし」表示）
  - 過去14日（今日含む）の日次ベスト棒グラフ。今日の行は強調表示
- ESC終了・ドリル完了は保存も画面表示もしない
- 既存テストはすべてpassする
- 新規ユニットテストもpassする

## スコープ外（YAGNI）

- ドリルモードのスコア記録
- スコア削除・編集UI
- 名前付け・複数プロファイル
- スコアエクスポート/インポート
- グローバルランキング/共有
- 古いレコードの自動削除（永久保持、サイズ問題が出てから対応）
