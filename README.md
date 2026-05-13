# AZIK Type (Ruby)

[jxmtst/azik-type](https://github.com/jxmtst/azik-type) のRuby/TUI移植。JavaScript/ブラウザ不使用。

## AZIKとは

AZIK（エイズィック）は、木村清氏が1994年に提案した拡張ローマ字入力方式。標準ローマ字入力と互換性を保ちつつ、`q` → 「ん」、`kt` → 「こと」などのショートカットで打鍵数を減らす。

## セットアップ

```sh
bundle install
```

## 実行

```sh
bin/az
```

- `ESC` / `Ctrl-C` — 終了
- `Tab` — モード切替（文章 / ドリル）

文章モードは60秒の時間制限、ドリルモードは10問。

## テスト

```sh
bundle exec rake test
```

## スコア記録

文章モードで制限時間を超過すると、KPM/正解率などを `~/.local/share/azik-typec/scores.jsonl`（`XDG_DATA_HOME` があればその配下）に追記し、終了直前に当日TOP5と過去14日の日次ベスト棒グラフを表示する。ドリル完了・ESC終了では記録しない。

## 構成

- `lib/azik/entries.rb` — ローマ字テーブル
- `lib/azik/decomposer.rb` — かな列→入力DAG
- `lib/azik/dag_shortest.rb` — 最短打鍵パス計算
- `lib/azik/input_matcher.rb` — カーソル管理・キー判定
- `lib/azik/metrics.rb` — KPM/正解率
- `lib/azik/score_record.rb` — スコアレコード値オブジェクト
- `lib/azik/score_store.rb` — JSONL 永続化
- `lib/azik/score_board.rb` — 集計・スコア画面描画
- `lib/azik/session.rb` — ドリル/文章セッション
- `lib/azik/tui.rb` — raw入力・ANSI描画
- `bin/az` — アプリ本体
