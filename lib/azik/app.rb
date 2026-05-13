$LOAD_PATH.unshift File.expand_path('..', __dir__) unless $LOAD_PATH.include?(File.expand_path('..', __dir__))

require 'azik'
require 'azik/entries'
require 'azik/decomposer'
require 'azik/input_matcher'
require 'azik/metrics'
require 'azik/session'
require 'azik/sentences'
require 'azik/tui'
require 'azik/score_record'
require 'azik/score_store'
require 'azik/score_board'

module Azik
  class App
    REFRESH_MS = 100

    def initialize
      @entries = Entries.load
      @decomposer = Decomposer.new(@entries)
      @mode = :sentence
      @acc = MetricsAccumulator.new
      @store = ScoreStore.new(path: ScoreStore.default_path)
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
      @finished = false
    end

    def next_question
      @acc.commit
      case @mode
      when :sentence
        @question = @session.next_question
      when :drill
        @session.advance
        if @session.finished?
          @finished = true
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
      @mode == :sentence && @started_at && elapsed_ms >= @session.time_limit_ms
    end

    GREY = '90'
    CYAN_BOLD = '1;36'
    GOLD = '93'
    RED = '31'

    def azik_shortcut?(edge)
      return false if edge.skip
      return true if edge.kana.length >= 2

      edge.kana == 'ん' && edge.romaji_options.first == 'q'
    end

    def question_text
      case @question
      when SentenceSession::Question then @question.text
      when DrillSession::Question then @question.kana
      end
    end

    # 最短経路上のエッジ列（ノード0から終端まで、最初のエッジを辿る）
    def plan
      items = []
      node = 0
      while node < @question.dag.node_count - 1
        edge_idx = @question.dag.edges_by_node[node]&.first
        break unless edge_idx

        edge = @question.dag.edges[edge_idx]
        items << edge
        node = edge.to
      end
      items
    end

    def typed_info
      if @matcher.cursors.empty?
        [@question.dag.node_count - 1, 0]
      else
        cursor = @matcher.cursors.min_by(&:node_id)
        [cursor.node_id, cursor.offset]
      end
    end

    def render_kana(plan, typed_node)
      plan.map do |edge|
        if edge.to <= typed_node
          TUI.color(edge.kana, GREY)
        elsif edge.from == typed_node
          TUI.color(edge.kana, CYAN_BOLD)
        elsif azik_shortcut?(edge)
          TUI.color(edge.kana, GOLD)
        else
          edge.kana
        end
      end.join
    end

    def render_romaji(plan, typed_node, current_offset)
      parts = []
      plan.each do |edge|
        next if edge.skip

        romaji = edge.romaji_options.first || ''
        if edge.to <= typed_node
          parts << TUI.color(romaji, GREY)
        elsif edge.from == typed_node
          if current_offset > 0
            parts << TUI.color(romaji[0, current_offset], GREY)
            parts << TUI.color(romaji[current_offset..], CYAN_BOLD)
          else
            parts << TUI.color(romaji, CYAN_BOLD)
          end
        elsif azik_shortcut?(edge)
          parts << TUI.color(romaji, GOLD)
        else
          parts << romaji
        end
      end
      parts.join
    end

    def render
      TUI.clear_screen
      TUI.move(1, 1)
      puts "=== AZIK Type [#{@mode}] ===\r"
      puts "\r"
      p = plan
      tn, off = typed_info
      puts "> #{render_kana(p, tn)}\r"
      puts "  #{render_romaji(p, tn, off)}\r"
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
      return :quit if ["\e", ""].include?(k)

      if k == "\t"
        @mode = (@mode == :sentence ? :drill : :sentence)
        new_session
        return
      end
      return unless k && k.length == 1 && k.match?(/[[:print:]]/)

      @started_at ||= Time.now
      result = InputMatcher.feed(@matcher, @question.dag, k)
      next_question if result == :complete
    end

    def build_score_record(metrics, now)
      ScoreRecord.new(
        timestamp: Time.at(now.to_i),
        mode: :sentence,
        raw_kpm: metrics.kpm,
        effective_kpm: metrics.effective_kpm,
        accuracy: metrics.accuracy,
        total_keystrokes: metrics.total_keystrokes,
        miss_count: metrics.miss_count,
        elapsed_ms: metrics.elapsed_ms
      )
    end

    def past_today_records(current_record)
      @store.load_all.reject { |r| r.timestamp == current_record.timestamp }
            .select { |r| r.timestamp.to_date == current_record.timestamp.to_date }
            .sort_by { |r| -r.effective_kpm }
    end

    def render_score_board(current_record)
      now = current_record.timestamp
      past_records = @store.load_all.reject { |r| r.timestamp == current_record.timestamp }
      board = ScoreBoard.new(records: past_records, now: now)
      today_past = past_today_records(current_record)
      TUI.clear_screen
      TUI.move(1, 1)
      puts "=== AZIK Type [スコア] ===\r"
      puts "\r"
      puts board.render_current(current_record).gsub("\n", "\r\n")
      puts "\r"
      puts board.render_top_of_day(today_past).gsub("\n", "\r\n")
      puts "\r"
      puts board.render_daily_chart(board.daily_bests(days: 14)).gsub("\n", "\r\n")
    end

    def run
      TUI.with_raw_mode do |io|
        loop do
          render
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
