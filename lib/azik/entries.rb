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
