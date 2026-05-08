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

## 構成

- `lib/azik/entries.rb` — ローマ字テーブル
- `lib/azik/decomposer.rb` — かな列→入力DAG
- `lib/azik/dag_shortest.rb` — 最短打鍵パス計算
- `lib/azik/input_matcher.rb` — カーソル管理・キー判定
- `lib/azik/metrics.rb` — KPM/正解率
- `lib/azik/session.rb` — ドリル/文章セッション
- `lib/azik/tui.rb` — raw入力・ANSI描画
- `bin/az` — アプリ本体
