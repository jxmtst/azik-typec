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
