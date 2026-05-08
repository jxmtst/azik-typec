# AZIK Type Ruby移植 実装計画

**Session:** `04ccdc1c-bbc1-4934-be95-9210eb7f1e15` (`claude --resume 04ccdc1c-bbc1-4934-be95-9210eb7f1e15` で会話に戻れる)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** TypeScript/Vite製ブラウザアプリ `jxmtst/azik-type` を Ruby単独（JS/ブラウザ不使用）のCLI/TUIアプリに移植する。

**Architecture:** 本家のエンジン構造（`decomposer` → `dagShortest` → `inputMatcher` → `session/metrics`）をRubyに素直に移植。UIはブラウザ不可のため `io/console` でraw入力を受け、ANSIエスケープで再描画するTUIを自前実装。`azik_romantable.txt` を単一データソースとして採用（TS側の自動生成 `azikData.ts` ではなく元表を直接読む）。

**Tech Stack:**
- Ruby 3.2+（標準添付 `io/console` でraw入力）
- `minitest`（テスト。標準添付）
- `unicode-display_width`（日本語の表示幅計算。唯一の実gem依存）
- `bundler`（gem管理）

**参考資料:**
- 本家リポジトリ: https://github.com/jxmtst/azik-type
- 本家コアファイル: `src/engine/{decomposer,dagShortest,inputMatcher,session,sessionMetrics}.ts`
- 本家テスト: `src/engine/__tests__/*.test.ts`
- データ: `azik_romantable.txt`（romaji→kana、タブ区切り、空行で章区切り）

---

## ファイル構成

**作成するファイル:**
- `Gemfile` — `unicode-display_width`, `minitest` 宣言
- `lib/azik.rb` — 全ファイルrequireのエントリ
- `lib/azik/entries.rb` — `azik_romantable.txt` ロード、kana→[{romaji, category, priority}] インデックス
- `lib/azik/decomposer.rb` — かな列 → InputDag 構築
- `lib/azik/dag_shortest.rb` — 最短路prune（本家 `dagShortest.ts` 相当）
- `lib/azik/input_matcher.rb` — カーソル管理・キー入力判定（progress/complete/error）
- `lib/azik/metrics.rb` — KPM・accuracy・effective KPM計算
- `lib/azik/sentences.rb` — 例文データ（本家 `src/data/sentences.ts` をRuby配列に移植）
- `lib/azik/session.rb` — DrillSession / SentenceSession
- `lib/azik/tui.rb` — raw入力・ANSI描画
- `bin/az` — エントリポイント（モード切替：sentence / drill）
- `data/azik_romantable.txt` — 本家からコピー
- `test/test_entries.rb` 他 — minitestテスト

**合計: Rubyファイル8本 + bin1本 + データ1本 + テスト6本程度。**

---

## Task 1: プロジェクト骨格

**Files:**
- Create: `Gemfile`
- Create: `Rakefile`
- Create: `.gitignore`
- Create: `lib/azik.rb`
- Create: `data/azik_romantable.txt`（本家からコピー）

- [ ] **Step 1: Gemfile作成**

```ruby
source 'https://rubygems.org'

gem 'unicode-display_width', '~> 2.5'

group :development, :test do
  gem 'minitest', '~> 5.20'
  gem 'rake', '~> 13.0'
end
```

- [ ] **Step 2: Rakefile作成（testタスク）**

```ruby
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.pattern = 'test/**/test_*.rb'
  t.warning = false
end

task default: :test
```

- [ ] **Step 3: .gitignore**

```
/.bundle/
/vendor/bundle
/Gemfile.lock
/tmp/
```

- [ ] **Step 4: lib/azik.rb スケルトン**

```ruby
module Azik
  ROOT = File.expand_path('..', __dir__)
  DATA_DIR = File.join(ROOT, 'data')
end
```

- [ ] **Step 5: azik_romantable.txt を本家からダウンロード**

Run: `curl -sL https://raw.githubusercontent.com/jxmtst/azik-type/main/azik_romantable.txt -o data/azik_romantable.txt && wc -l data/azik_romantable.txt`
Expected: 約700行

- [ ] **Step 6: bundle install**

Run: `bundle install`
Expected: 成功

- [ ] **Step 7: Commit**

```bash
git init && git add -A
git commit -m "chore: initial project skeleton with Gemfile and romantable data"
```

---

## Task 2: Entries（romantableロード）

**本家参照:** `src/data/azikData.ts` の `AZIK_ENTRIES`, `KANA_TO_ENTRIES`, `getShortestRomaji`。ただし本Rubyは `azik_romantable.txt` を直接パースする。

`azik_romantable.txt` のフォーマット:
- 空行は無視
- `romaji<TAB>kana` 各行
- カテゴリ情報は元表に無いため、本実装では category を付けず、`{romaji:, kana:, priority: romaji.length}` のみを保持する（ドリル機能はカテゴリ非依存のシンプル実装にする — Task 10参照）

**Files:**
- Create: `lib/azik/entries.rb`
- Create: `test/test_entries.rb`

- [ ] **Step 1: failing testを書く**

```ruby
# test/test_entries.rb
require 'minitest/autorun'
require 'azik/entries'

class TestEntries < Minitest::Test
  def setup
    @entries = Azik::Entries.load
  end

  def test_loads_basic_mappings
    ka = @entries.lookup_kana('か')
    refute_nil ka
    assert_includes ka.map(&:romaji), 'ka'
  end

  def test_loads_azik_shortcut
    n = @entries.lookup_kana('ん')
    assert_includes n.map(&:romaji), 'q'
  end

  def test_loads_compound_word
    koto = @entries.lookup_kana('こと')
    assert_includes koto.map(&:romaji), 'kt'
  end

  def test_shortest_romaji_for_kana
    # 「ん」は q(1) と nn(2) → q のみ
    assert_equal ['q'], @entries.shortest_romaji('ん')
  end

  def test_shortest_romaji_returns_all_equal_length
    # 「さん」は sz(2) と sn(2) → 両方
    result = @entries.shortest_romaji('さん')
    assert_equal 2, result.size
    assert_includes result, 'sz'
    assert_includes result, 'sn'
  end

  def test_unknown_kana_returns_nil
    assert_nil @entries.lookup_kana('漢')
  end
end
```

- [ ] **Step 2: テスト実行（失敗確認）**

Run: `bundle exec rake test TESTOPTS='-n /entries/'`
Expected: FAIL（`cannot load such file -- azik/entries`）

- [ ] **Step 3: 実装**

```ruby
# lib/azik/entries.rb
require 'azik'

module Azik
  class Entries
    Entry = Struct.new(:romaji, :kana, :priority, keyword_init: true)

    def self.load(path = File.join(Azik::DATA_DIR, 'azik_romantable.txt'))
      entries = []
      File.foreach(path, chomp: true) do |line|
        next if line.strip.empty?
        romaji, kana = line.split("\t", 2)
        next if romaji.nil? || kana.nil?
        entries << Entry.new(romaji: romaji, kana: kana, priority: romaji.length)
      end
      new(entries)
    end

    def initialize(entries)
      @entries = entries
      @by_kana = entries.group_by(&:kana)
    end

    attr_reader :entries

    def lookup_kana(kana)
      @by_kana[kana]
    end

    def shortest_romaji(kana)
      list = @by_kana[kana] or return nil
      min_len = list.map { |e| e.romaji.length }.min
      list.select { |e| e.romaji.length == min_len }.map(&:romaji)
    end
  end
end
```

- [ ] **Step 4: テスト実行（成功確認）**

Run: `bundle exec rake test TESTOPTS='-n /entries/'`
Expected: 6 runs, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/azik.rb lib/azik/entries.rb test/test_entries.rb
git commit -m "feat: load azik romantable and index by kana"
```

---

## Task 3: Decomposer（かな列→DAG）

**本家参照:** `src/engine/decomposer.ts` と `src/engine/__tests__/decomposer.test.ts`。DAG構造体:

```
Dag = { node_count: Integer, edges: [Edge], edges_by_node: [[edge_idx]] }
Edge = { from:, to:, romaji_options: [String], kana: String, skip: Boolean }
```

NFKC正規化ルール: 本家は `NFKC_PRESERVE = {'…', '‥'}` 以外はNFKCで分解。Ruby標準は `String#unicode_normalize(:nfkc)`。

**Files:**
- Create: `lib/azik/dag.rb` — Dag/Edge Struct定義
- Create: `lib/azik/decomposer.rb`
- Create: `test/test_decomposer.rb`

- [ ] **Step 1: Dag struct定義**

```ruby
# lib/azik/dag.rb
module Azik
  Edge = Struct.new(:from, :to, :romaji_options, :kana, :skip, keyword_init: true) do
    def skip?; skip; end
  end

  Dag = Struct.new(:node_count, :edges, :edges_by_node, keyword_init: true)
end
```

- [ ] **Step 2: failing test**

```ruby
# test/test_decomposer.rb
require 'minitest/autorun'
require 'azik/decomposer'

class TestDecomposer < Minitest::Test
  def setup
    @entries = Azik::Entries.load
    @dec = Azik::Decomposer.new(@entries)
  end

  def test_single_kana_dag
    dag = @dec.decompose('か')
    assert_equal 2, dag.node_count
    assert_equal 1, dag.edges.size
    assert_includes dag.edges[0].romaji_options, 'ka'
    assert_equal 'か', dag.edges[0].kana
  end

  def test_compound_shortcut_prunes_non_shortest
    # 「こと」は kt のみ、ko+to は枝刈り
    dag = @dec.decompose('こと')
    assert_equal 3, dag.node_count
    edges_from_0 = dag.edges_by_node[0].map { |i| dag.edges[i] }
    assert_equal 1, edges_from_0.size
    assert_equal 'こと', edges_from_0[0].kana
    assert_includes edges_from_0[0].romaji_options, 'kt'
    assert_equal 2, edges_from_0[0].to
  end

  def test_non_target_char_becomes_skip_edge
    dag = @dec.decompose('あ字か')
    skip_edges = dag.edges.select(&:skip?)
    assert_equal 1, skip_edges.size
    assert_equal '字', skip_edges[0].kana
  end

  def test_punctuation_is_input_target
    dag = @dec.decompose('あ。')
    period = dag.edges.find { |e| e.kana == '。' }
    refute_nil period
    refute period.skip?
    assert_includes period.romaji_options, '.'
  end

  def test_empty_string
    dag = @dec.decompose('')
    assert_equal 1, dag.node_count
    assert_empty dag.edges
  end

  def test_shortest_only_for_single_kana
    # 「ん」は q のみ、nn は除外
    dag = @dec.decompose('ん')
    edge = dag.edges[0]
    assert_includes edge.romaji_options, 'q'
    refute_includes edge.romaji_options, 'nn'
  end
end
```

- [ ] **Step 3: テスト失敗確認**

Run: `bundle exec rake test TESTOPTS='-n /decompos/'`
Expected: FAIL

- [ ] **Step 4: Decomposer実装（prune前、初期DAG構築）**

```ruby
# lib/azik/decomposer.rb
require 'azik'
require 'azik/entries'
require 'azik/dag'
require 'azik/dag_shortest'

module Azik
  class Decomposer
    NFKC_PRESERVE = ['…', '‥'].freeze
    MAX_MATCH_LEN = 4

    def initialize(entries)
      @entries = entries
    end

    def decompose(input)
      chars = split_chars(input)
      node_count = chars.size + 1
      edges = []
      edges_by_node = Array.new(node_count) { [] }

      chars.each_with_index do |ch, i|
        list_here = @entries.lookup_kana(ch)
        if list_here.nil?
          idx = edges.size
          edges << Edge.new(from: i, to: i + 1, romaji_options: [], kana: ch, skip: true)
          edges_by_node[i] << idx
          next
        end

        # 1文字マッチ
        opts1 = @entries.shortest_romaji(ch)
        if opts1 && !opts1.empty?
          idx = edges.size
          edges << Edge.new(from: i, to: i + 1, romaji_options: opts1, kana: ch, skip: false)
          edges_by_node[i] << idx
        end

        # 2〜MAX_MATCH_LEN文字マッチ（複合語）
        (2..[chars.size - i, MAX_MATCH_LEN].min).each do |len|
          substr = chars[i, len].join
          opts = @entries.shortest_romaji(substr)
          next if opts.nil? || opts.empty?
          idx = edges.size
          edges << Edge.new(from: i, to: i + len, romaji_options: opts, kana: substr, skip: false)
          edges_by_node[i] << idx
        end
      end

      dag = Dag.new(node_count: node_count, edges: edges, edges_by_node: edges_by_node)
      DagShortest.prune(dag)
    end

    private

    def split_chars(input)
      chars = []
      input.each_char do |ch|
        if NFKC_PRESERVE.include?(ch)
          chars << ch
        else
          ch.unicode_normalize(:nfkc).each_char { |c| chars << c }
        end
      end
      chars
    end
  end
end
```

- [ ] **Step 5: DagShortestスタブ（恒等関数）でまず動作確認**

このステップはTask 4の正式実装までの仮置き。次タスクで置き換える。

```ruby
# lib/azik/dag_shortest.rb (一時スタブ)
module Azik
  module DagShortest
    def self.prune(dag)
      dag
    end
  end
end
```

- [ ] **Step 6: テスト（prune依存分は失敗するが、基本構築は通る）**

Run: `bundle exec rake test TESTOPTS='-n /decompos/'`
Expected: `test_compound_shortcut_prunes_non_shortest` 失敗。他はPASS。

- [ ] **Step 7: Commit**

```bash
git add lib/azik/dag.rb lib/azik/decomposer.rb lib/azik/dag_shortest.rb test/test_decomposer.rb
git commit -m "feat: decompose kana string into input DAG"
```

---

## Task 4: DagShortest（最短路prune）

**本家参照:** `src/engine/dagShortest.ts`。アルゴリズムは後ろから DP:

- `dist[終端] = 0`
- `dist[i] = min over edges from i of (skip ? dist[to] : min_romaji_len + dist[to])`
- 最短経路上のエッジのみ残す: `minLen + dist[to] == dist[from]`

**Files:**
- Modify: `lib/azik/dag_shortest.rb`
- Create: `test/test_dag_shortest.rb`

- [ ] **Step 1: failing test**

```ruby
# test/test_dag_shortest.rb
require 'minitest/autorun'
require 'azik/decomposer'

class TestDagShortest < Minitest::Test
  def setup
    @dec = Azik::Decomposer.new(Azik::Entries.load)
  end

  def test_koto_prunes_non_shortest
    dag = @dec.decompose('こと')
    edges_from_0 = dag.edges_by_node[0].map { |i| dag.edges[i] }
    assert_equal 1, edges_from_0.size
    assert_equal 'こと', edges_from_0[0].kana
  end

  def test_kotogaaru_shortest_only
    dag = @dec.decompose('ことがある')
    edges_from_0 = dag.edges_by_node[0].map { |i| dag.edges[i] }
    assert_equal 1, edges_from_0.size
    assert_equal 'こと', edges_from_0[0].kana
  end

  def test_skip_edge_retained
    dag = @dec.decompose('あ字か')
    # skip edgeは最短経路の一部として残る
    skip_edges = dag.edges.select(&:skip?)
    assert_equal 1, skip_edges.size
    # edges_by_nodeに含まれているか
    assert(dag.edges_by_node[1].any? { |i| dag.edges[i].skip? })
  end
end
```

- [ ] **Step 2: テスト失敗確認**

Run: `bundle exec rake test TESTOPTS='-n /dag_shortest|decompos/'`
Expected: FAIL（上記テスト + Task3で残ったテスト）

- [ ] **Step 3: 正式実装**

```ruby
# lib/azik/dag_shortest.rb
module Azik
  module DagShortest
    INF = Float::INFINITY

    def self.compute_shortest_dist(dag)
      n = dag.node_count
      dist = Array.new(n, INF)
      dist[n - 1] = 0
      (n - 2).downto(0) do |i|
        (dag.edges_by_node[i] || []).each do |edge_idx|
          edge = dag.edges[edge_idx]
          cost = if edge.skip?
                   dist[edge.to]
                 else
                   edge.romaji_options.map(&:length).min + dist[edge.to]
                 end
          dist[i] = cost if cost < dist[i]
        end
      end
      dist
    end

    def self.prune(dag)
      dist = compute_shortest_dist(dag)
      n = dag.node_count
      new_by_node = Array.new(n) { [] }
      n.times do |i|
        (dag.edges_by_node[i] || []).each do |edge_idx|
          edge = dag.edges[edge_idx]
          cost = if edge.skip?
                   dist[edge.to]
                 else
                   edge.romaji_options.map(&:length).min + dist[edge.to]
                 end
          new_by_node[i] << edge_idx if cost == dist[i]
        end
      end
      Dag.new(node_count: n, edges: dag.edges, edges_by_node: new_by_node)
    end
  end
end
```

- [ ] **Step 4: テスト成功確認**

Run: `bundle exec rake test TESTOPTS='-n /dag_shortest|decompos/'`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/azik/dag_shortest.rb test/test_dag_shortest.rb
git commit -m "feat: prune DAG to shortest romaji paths"
```

---

## Task 5: InputMatcher（カーソル管理・キー判定）

**本家参照:** `src/engine/inputMatcher.ts` と同 `__tests__/inputMatcher.test.ts`。

コアアルゴリズム:
- `Cursor = {node_id, edge_index, offset}`
- `create_matcher(dag)` — ノード0から ε-closure 展開
- `feed_key(state, dag, key)` — 各カーソルで `romaji[offset] == key` を試す。進めば更新、romajiを完走したら次ノードへ ε-closure 展開
- ε遷移: `edge.skip?` の場合自動で辿る（キー消費なし）
- 戻り値: `:progress | :complete | :error`
- `totalKeystrokes` は判定前にインクリメント。error時は savedCursors に戻す

**Files:**
- Create: `lib/azik/input_matcher.rb`
- Create: `test/test_input_matcher.rb`

- [ ] **Step 1: failing test（本家testを移植）**

```ruby
# test/test_input_matcher.rb
require 'minitest/autorun'
require 'azik/input_matcher'
require 'azik/decomposer'

class TestInputMatcher < Minitest::Test
  def setup
    @dec = Azik::Decomposer.new(Azik::Entries.load)
  end

  def test_single_ka_complete
    dag = @dec.decompose('か')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'a')
  end

  def test_miss_restores_cursors
    dag = @dec.decompose('か')
    state = Azik::InputMatcher.create(dag)
    Azik::InputMatcher.feed(state, dag, 'k')
    before = Marshal.dump(state.cursors)
    assert_equal :error, Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal before, Marshal.dump(state.cursors)
    assert_equal 1, state.miss_count
    assert_equal 2, state.total_keystrokes
  end

  def test_recover_after_miss
    dag = @dec.decompose('か')
    state = Azik::InputMatcher.create(dag)
    Azik::InputMatcher.feed(state, dag, 'k')
    Azik::InputMatcher.feed(state, dag, 'x')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'a')
  end

  def test_compound_shortcut_kt
    dag = @dec.decompose('こと')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 't')
  end

  def test_compound_rejects_non_shortest
    dag = @dec.decompose('こと')
    state = Azik::InputMatcher.create(dag)
    Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal :error, Azik::InputMatcher.feed(state, dag, 'o')
  end

  def test_total_keystrokes_counts_misses
    dag = @dec.decompose('あ')
    state = Azik::InputMatcher.create(dag)
    Azik::InputMatcher.feed(state, dag, 'x')
    Azik::InputMatcher.feed(state, dag, 'a')
    assert_equal 2, state.total_keystrokes
    assert_equal 1, state.miss_count
  end

  def test_epsilon_auto_skip
    dag = @dec.decompose('あ字い')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'a')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'i')
  end

  def test_uppercase_input_accepted
    dag = @dec.decompose('か')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'K')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'A')
  end

  def test_tenki_shortest_only
    # てんき: td(てん) + ki = 最短
    dag = @dec.decompose('てんき')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 't')
    assert_equal :error,    Azik::InputMatcher.feed(state, dag, 'e')
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'd')
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'i')
  end

  def test_empty_dag
    dag = @dec.decompose('')
    state = Azik::InputMatcher.create(dag)
    assert_empty state.cursors
  end
end
```

- [ ] **Step 2: テスト失敗確認**

Run: `bundle exec rake test TESTOPTS='-n /input_matcher/'`
Expected: FAIL

- [ ] **Step 3: 実装**

```ruby
# lib/azik/input_matcher.rb
require 'azik/dag'

module Azik
  module InputMatcher
    Cursor = Struct.new(:node_id, :edge_index, :offset, keyword_init: true) do
      def key_tuple; [node_id, edge_index, offset]; end
    end

    class State
      attr_accessor :cursors, :total_keystrokes, :miss_count
      def initialize
        @cursors = []
        @total_keystrokes = 0
        @miss_count = 0
      end
    end

    def self.create(dag)
      state = State.new
      return state if dag.node_count <= 1
      state.cursors = expand_epsilon(dag, 0)
      state
    end

    def self.feed(state, dag, key)
      k = key.downcase
      state.total_keystrokes += 1
      saved = state.cursors.map(&:dup)
      seen = {}
      next_cursors = []

      state.cursors.each do |cursor|
        edge = dag.edges[cursor.edge_index]
        edge.romaji_options.each do |romaji|
          next unless cursor.offset < romaji.length && romaji[cursor.offset] == k
          new_offset = cursor.offset + 1
          if new_offset >= romaji.length
            expanded = expand_epsilon(dag, edge.to)
            if can_reach_terminal?(dag, edge.to) && expanded.empty?
              state.cursors = []
              return :complete
            end
            expanded.each do |nc|
              next if seen[nc.key_tuple]
              seen[nc.key_tuple] = true
              next_cursors << nc
            end
          else
            adv = Cursor.new(node_id: cursor.node_id, edge_index: cursor.edge_index, offset: new_offset)
            next if seen[adv.key_tuple]
            seen[adv.key_tuple] = true
            next_cursors << adv
          end
        end
      end

      if next_cursors.empty?
        state.cursors = saved
        state.miss_count += 1
        return :error
      end

      state.cursors = next_cursors
      :progress
    end

    def self.current_kana_position(state)
      return 0 if state.cursors.empty?
      state.cursors.map(&:node_id).min
    end

    def self.expand_epsilon(dag, node_id)
      cursors = []
      visited = {}
      queue = [node_id]
      until queue.empty?
        nid = queue.shift
        next if visited[nid]
        visited[nid] = true
        (dag.edges_by_node[nid] || []).each do |edge_idx|
          edge = dag.edges[edge_idx]
          if edge.skip?
            queue << edge.to
          else
            cursors << Cursor.new(node_id: nid, edge_index: edge_idx, offset: 0)
          end
        end
      end
      cursors
    end

    def self.can_reach_terminal?(dag, node_id)
      terminal = dag.node_count - 1
      visited = {}
      queue = [node_id]
      until queue.empty?
        nid = queue.shift
        next if visited[nid]
        visited[nid] = true
        return true if nid == terminal
        (dag.edges_by_node[nid] || []).each do |edge_idx|
          edge = dag.edges[edge_idx]
          queue << edge.to if edge.skip?
        end
      end
      false
    end
  end
end
```

- [ ] **Step 4: テスト成功確認**

Run: `bundle exec rake test TESTOPTS='-n /input_matcher/'`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/azik/input_matcher.rb test/test_input_matcher.rb
git commit -m "feat: input matcher with cursor-based key feeding"
```

---

## Task 6: Metrics（KPM/accuracy計算）

**本家参照:** `src/engine/sessionMetrics.ts` および `types.ts` の `SessionMetrics`。

計算式:
- KPM = `totalKeystrokes / (elapsedMs / 60000)`
- accuracy = `1 - missCount / totalKeystrokes`（totalが0なら1.0）
- effective KPM = `KPM * accuracy`

**Files:**
- Create: `lib/azik/metrics.rb`
- Create: `test/test_metrics.rb`

- [ ] **Step 1: failing test**

```ruby
# test/test_metrics.rb
require 'minitest/autorun'
require 'azik/metrics'

class TestMetrics < Minitest::Test
  def test_basic_kpm
    m = Azik::Metrics.new(total_keystrokes: 60, miss_count: 0, elapsed_ms: 60_000)
    assert_in_delta 60.0, m.kpm, 0.01
    assert_in_delta 1.0, m.accuracy, 0.01
    assert_in_delta 60.0, m.effective_kpm, 0.01
  end

  def test_accuracy_with_misses
    m = Azik::Metrics.new(total_keystrokes: 100, miss_count: 10, elapsed_ms: 60_000)
    assert_in_delta 0.9, m.accuracy, 0.001
    assert_in_delta 90.0, m.effective_kpm, 0.1
  end

  def test_zero_keystrokes
    m = Azik::Metrics.new(total_keystrokes: 0, miss_count: 0, elapsed_ms: 1000)
    assert_equal 0.0, m.kpm
    assert_equal 1.0, m.accuracy
  end

  def test_accumulator
    acc = Azik::MetricsAccumulator.new
    acc.update(total_keystrokes: 10, miss_count: 1, elapsed_ms: 10_000)
    acc.commit
    acc.update(total_keystrokes: 5, miss_count: 0, elapsed_ms: 15_000)
    m = acc.current
    assert_equal 15, m.total_keystrokes
    assert_equal 1, m.miss_count
    assert_equal 15_000, m.elapsed_ms
  end
end
```

- [ ] **Step 2: テスト失敗確認**

Run: `bundle exec rake test TESTOPTS='-n /metrics/'`
Expected: FAIL

- [ ] **Step 3: 実装**

```ruby
# lib/azik/metrics.rb
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
```

- [ ] **Step 4: テスト成功確認**

Run: `bundle exec rake test TESTOPTS='-n /metrics/'`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/azik/metrics.rb test/test_metrics.rb
git commit -m "feat: session metrics with KPM and accuracy"
```

---

## Task 7: Sentences データ移植

**本家参照:** `src/data/sentences.ts`。配列を Ruby に移植。

**Files:**
- Create: `lib/azik/sentences.rb`

- [ ] **Step 1: 本家ファイルから抽出**

Run: `curl -sL https://raw.githubusercontent.com/jxmtst/azik-type/main/src/data/sentences.ts | grep -oE "'[^']+'" | head -5`
Expected: 例文が抽出される

- [ ] **Step 2: Rubyファイル生成**

次のワンライナーで `sentences.ts` → `sentences.rb` 変換:

```bash
curl -sL https://raw.githubusercontent.com/jxmtst/azik-type/main/src/data/sentences.ts \
  | ruby -e '
    lines = STDIN.read.scan(/'"'"'([^'"'"']+)'"'"'/).flatten
    puts "module Azik"
    puts "  SENTENCES = ["
    lines.each { |l| puts "    #{l.inspect}," }
    puts "  ].freeze"
    puts "end"
  ' > lib/azik/sentences.rb
wc -l lib/azik/sentences.rb
```

Expected: 数十〜百行程度

- [ ] **Step 3: ロードテスト（手動）**

Run: `ruby -Ilib -razik/sentences -e 'puts Azik::SENTENCES.size; puts Azik::SENTENCES.first'`
Expected: 件数と最初の例文が出力

- [ ] **Step 4: Commit**

```bash
git add lib/azik/sentences.rb
git commit -m "feat: port sentences data from upstream"
```

---

## Task 8: Session（ドリル・文章モード）

**本家参照:** `src/engine/session.ts`。

**Files:**
- Create: `lib/azik/session.rb`
- Create: `test/test_session.rb`

簡略化方針（本家との差分）:
- `DrillSession` はエントリ全件からランダムに N問選ぶ（カテゴリフィルタは本実装では省略 — `azik_romantable.txt` にcategory情報が無いため）
- `SentenceSession` は本家同様、時間制限と例文シャッフル

- [ ] **Step 1: failing test**

```ruby
# test/test_session.rb
require 'minitest/autorun'
require 'azik/session'

class TestSession < Minitest::Test
  def setup
    @decomposer = Azik::Decomposer.new(Azik::Entries.load)
  end

  def test_drill_session_generates_questions
    s = Azik::DrillSession.new(entries: Azik::Entries.load, decomposer: @decomposer, count: 5)
    assert_equal 5, s.questions.size
    assert_equal 0, s.current_index
    first = s.questions.first
    refute_nil first.dag
    assert_kind_of String, first.kana
  end

  def test_sentence_session_next_question
    s = Azik::SentenceSession.new(decomposer: @decomposer, time_limit_sec: 60, sentences: %w[あい うえ])
    q1 = s.next_question
    assert_includes %w[あい うえ], q1.text
    q2 = s.next_question
    refute_nil q2.dag
  end

  def test_sentence_session_wraps_around
    s = Azik::SentenceSession.new(decomposer: @decomposer, time_limit_sec: 60, sentences: ['あ'])
    2.times { s.next_question }
    # 2回目も取得できる（再シャッフル）
    assert_kind_of Azik::SentenceSession::Question, s.current_question
  end
end
```

- [ ] **Step 2: テスト失敗確認**

Run: `bundle exec rake test TESTOPTS='-n /session/'`
Expected: FAIL

- [ ] **Step 3: 実装**

```ruby
# lib/azik/session.rb
require 'azik/decomposer'
require 'azik/sentences'

module Azik
  class DrillSession
    Question = Struct.new(:kana, :dag, keyword_init: true)

    attr_reader :questions
    attr_accessor :current_index

    def initialize(entries:, decomposer:, count:, rng: Random.new)
      unique_kanas = entries.entries.map(&:kana).uniq
      picked = unique_kanas.shuffle(random: rng).first([count, unique_kanas.size].min)
      @questions = picked.map { |k| Question.new(kana: k, dag: decomposer.decompose(k)) }
      @current_index = 0
    end

    def current
      @questions[@current_index]
    end

    def advance
      @current_index += 1
    end

    def finished?
      @current_index >= @questions.size
    end
  end

  class SentenceSession
    Question = Struct.new(:text, :dag, keyword_init: true)

    attr_reader :time_limit_ms, :current_question

    def initialize(decomposer:, time_limit_sec:, sentences: Azik::SENTENCES, rng: Random.new)
      @decomposer = decomposer
      @time_limit_ms = time_limit_sec * 1000
      @pool = sentences.dup
      @rng = rng
      @shuffled = @pool.shuffle(random: @rng)
      @index = 0
      @current_question = nil
    end

    def next_question
      if @index >= @shuffled.size
        @shuffled = @pool.shuffle(random: @rng)
        @index = 0
      end
      text = @shuffled[@index]
      @index += 1
      @current_question = Question.new(text: text, dag: @decomposer.decompose(text))
      @current_question
    end
  end
end
```

- [ ] **Step 4: テスト成功確認**

Run: `bundle exec rake test TESTOPTS='-n /session/'`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/azik/session.rb test/test_session.rb
git commit -m "feat: drill and sentence session orchestration"
```

---

## Task 9: TUI（raw入力・ANSI描画）

**ブラウザ版との非互換点:**
- ブラウザ版は文字色ハイライト/キーマップ可視化があるが、TUI版は現在入力中のかな位置を強調表示するのみ（最小実装）
- キーマップモードは省略（YAGNI）

画面レイアウト:
```
=== AZIK Type [sentence mode] ===

かだい: けいえいせんりゃくをさいけんとうする。
        ^^^^^^ここまで入力済^^^^^^[ここが現在位置]残り...
ろーまじ: keieisenryaku...

残り時間: 45s  KPM: 120.3  正解率: 98.2%  missed: 1
[ESC=quit | Tab=drill mode]
```

**Files:**
- Create: `lib/azik/tui.rb`

- [ ] **Step 1: TUI基本構造実装**

```ruby
# lib/azik/tui.rb
require 'io/console'
require 'unicode/display_width'

module Azik
  module TUI
    CSI = "\e["

    module_function

    def with_raw_mode
      $stdin.raw do |io|
        print "#{CSI}?25l" # hide cursor
        yield io
      ensure
        print "#{CSI}?25h" # show cursor
        print "\n"
      end
    end

    def clear_screen
      print "#{CSI}2J#{CSI}H"
    end

    def move(row, col)
      print "#{CSI}#{row};#{col}H"
    end

    def color(text, code)
      "#{CSI}#{code}m#{text}#{CSI}0m"
    end

    def read_key(io)
      ch = io.getc
      return nil if ch.nil?
      # ESC系のシーケンス対応
      if ch == "\e"
        begin
          seq = io.read_nonblock(4)
          return "\e#{seq}"
        rescue IO::WaitReadable, EOFError
          return "\e"
        end
      end
      ch
    end

    def display_width(s)
      Unicode::DisplayWidth.of(s)
    end
  end
end
```

- [ ] **Step 2: 手動動作確認**

Run:
```bash
ruby -Ilib -razik/tui -e '
Azik::TUI.with_raw_mode do |io|
  Azik::TUI.clear_screen
  puts "Press keys, ESC to quit"
  loop do
    k = Azik::TUI.read_key(io)
    break if k == "\e" || k == "\u0003"
    print "got: #{k.inspect}\r\n"
  end
end
'
```
Expected: キー押下でecho、ESC/Ctrl-Cで終了

- [ ] **Step 3: Commit**

```bash
git add lib/azik/tui.rb
git commit -m "feat: raw terminal input and ANSI drawing primitives"
```

---

## Task 10: アプリ本体（bin/az）

**Files:**
- Create: `bin/az`

機能:
- 起動時は sentence モード（60秒）
- Tab: ドリルモード（10問）と sentence モードを切替
- ESC: 現在の問題をリセット/終了
- 1文字入力ごとに InputMatcher#feed → 完了で次問
- 下部に KPM / accuracy / 残り時間 表示

- [ ] **Step 1: 実装**

```ruby
#!/usr/bin/env ruby
# bin/az
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'azik'
require 'azik/entries'
require 'azik/decomposer'
require 'azik/input_matcher'
require 'azik/metrics'
require 'azik/session'
require 'azik/sentences'
require 'azik/tui'

module Azik
  class App
    REFRESH_MS = 100

    def initialize
      @entries = Entries.load
      @decomposer = Decomposer.new(@entries)
      @mode = :sentence
      @acc = MetricsAccumulator.new
      new_session
    end

    def new_session
      @acc.reset
      case @mode
      when :sentence
        @session = SentenceSession.new(decomposer: @decomposer, time_limit_sec: 60)
        @question = @session.next_question
      when :drill
        @session = DrillSession.new(entries: @entries, decomposer: @decomposer, count: 10)
        @question = @session.current
      end
      @matcher = InputMatcher.create(@question.dag)
      @started_at = nil
    end

    def next_question
      @acc.commit
      case @mode
      when :sentence
        @question = @session.next_question
      when :drill
        @session.advance
        if @session.finished?
          finish
          return
        end
        @question = @session.current
      end
      @matcher = InputMatcher.create(@question.dag)
    end

    def elapsed_ms
      return 0 unless @started_at
      ((Time.now - @started_at) * 1000).to_i
    end

    def time_up?
      @mode == :sentence && elapsed_ms >= @session.time_limit_ms
    end

    def finish
      @finished = true
    end

    def finished?
      @finished
    end

    def render
      TUI.clear_screen
      TUI.move(1, 1)
      puts "=== AZIK Type [#{@mode}] ===\r"
      puts "\r"
      case @question
      when SentenceSession::Question
        puts "かだい: #{@question.text}\r"
      when DrillSession::Question
        puts "かだい: #{@question.kana}\r"
      end
      pos = InputMatcher.current_kana_position(@matcher)
      puts "位置:    #{' ' * pos}^\r"
      puts "\r"
      @acc.update(total_keystrokes: @matcher.total_keystrokes, miss_count: @matcher.miss_count, elapsed_ms: elapsed_ms)
      m = @acc.current
      remaining = @mode == :sentence ? [(@session.time_limit_ms - elapsed_ms) / 1000, 0].max : '-'
      puts format("残り: %ss  KPM: %.1f  正解率: %.1f%%  miss: %d\r",
                  remaining, m.kpm, m.accuracy * 100, m.miss_count)
      puts "\r"
      puts "[ESC=quit | Tab=toggle mode]\r"
    end

    def handle_key(k)
      return :quit if k == "\e" || k == "\u0003"
      if k == "\t"
        @mode = (@mode == :sentence ? :drill : :sentence)
        new_session
        return
      end
      return unless k && k.length == 1 && k =~ /[[:print:]]/
      @started_at ||= Time.now
      result = InputMatcher.feed(@matcher, @question.dag, k)
      next_question if result == :complete
    end

    def run
      TUI.with_raw_mode do |io|
        loop do
          render
          if time_up? || finished?
            puts "\r\nFinished. Press any key to exit.\r"
            io.getc
            break
          end
          # ノンブロッキング読み取りで残時間更新
          begin
            ready = IO.select([io], nil, nil, REFRESH_MS / 1000.0)
            if ready
              k = TUI.read_key(io)
              break if handle_key(k) == :quit
            end
          rescue Interrupt
            break
          end
        end
      end
    end
  end
end

Azik::App.new.run
```

- [ ] **Step 2: 実行権限**

Run: `chmod +x bin/az && ls -l bin/az`
Expected: `-rwxr-xr-x`

- [ ] **Step 3: 手動動作確認**

Run: `bin/az`
Expected: 画面が表示され、かな入力で進行、Tab/ESCが機能

- [ ] **Step 4: Commit**

```bash
git add bin/az
git commit -m "feat: TUI app entry point with sentence and drill modes"
```

---

## Task 11: READMEとスモークテスト

**Files:**
- Create: `README.md`
- Create: `test/test_smoke.rb`

- [ ] **Step 1: スモークテスト（全体結合）**

```ruby
# test/test_smoke.rb
require 'minitest/autorun'
require 'azik/decomposer'
require 'azik/input_matcher'

class TestSmoke < Minitest::Test
  def setup
    @dec = Azik::Decomposer.new(Azik::Entries.load)
  end

  def test_sentence_completion
    text = 'あいうえお'
    dag = @dec.decompose(text)
    state = Azik::InputMatcher.create(dag)
    result = nil
    'aiueo'.each_char { |c| result = Azik::InputMatcher.feed(state, dag, c) }
    assert_equal :complete, result
    assert_equal 0, state.miss_count
  end

  def test_azik_shortcut_sentence
    # 「てんき」は tdki（4キー）で完走
    text = 'てんき'
    dag = @dec.decompose(text)
    state = Azik::InputMatcher.create(dag)
    result = nil
    'tdki'.each_char { |c| result = Azik::InputMatcher.feed(state, dag, c) }
    assert_equal :complete, result
  end
end
```

- [ ] **Step 2: テスト成功確認**

Run: `bundle exec rake test`
Expected: 全テストPASS

- [ ] **Step 3: README作成**

```markdown
# AZIK Type (Ruby)

[jxmtst/azik-type](https://github.com/jxmtst/azik-type) のRuby/TUI移植。

## セットアップ

    bundle install

## 実行

    bin/az

- `ESC` 終了
- `Tab` モード切替（文章/ドリル）

## テスト

    bundle exec rake test
```

- [ ] **Step 4: Commit**

```bash
git add README.md test/test_smoke.rb
git commit -m "docs: readme and smoke tests"
```

---

## 自己レビュー

**カバレッジ:**
- エンジン（decomposer, dag_shortest, input_matcher, metrics）: Task 3-6 ✓
- セッション（drill/sentence）: Task 8 ✓
- データ（romantable, sentences）: Task 1, 7 ✓
- UI（raw入力, 描画, アプリ制御）: Task 9, 10 ✓
- テスト: 全エンジン + スモーク ✓

**省略した本家機能（意識的なYAGNI）:**
- キーマップモード（Task 10 で明記）
- scoreStorage（localStorage前提のため不要）
- hintBuilder（現行TUIはシンプル表示なので未使用）
- カテゴリ別ドリル（romantable.txtにcategory情報が無い。必要になれば `azikData.ts` を別途パースして追加）

**型整合:**
- `InputMatcher.State#cursors/total_keystrokes/miss_count` — Task 5で定義、Task 10で参照 ✓
- `MetricsAccumulator#update/commit/current` — Task 6定義、Task 10呼び出し ✓
- `Dag/Edge` — Task 3定義、Task 4/5/8で参照 ✓
