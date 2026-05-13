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
