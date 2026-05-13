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
