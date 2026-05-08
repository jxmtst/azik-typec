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
        opts1 = @entries.shortest_romaji(ch)
        if opts1 && !opts1.empty?
          idx = edges.size
          edges << Edge.new(from: i, to: i + 1, romaji_options: opts1, kana: ch, skip: false)
          edges_by_node[i] << idx
        end

        any_multi = false
        (2..[chars.size - i, MAX_MATCH_LEN].min).each do |len|
          substr = chars[i, len].join
          opts = @entries.shortest_romaji(substr)
          next if opts.nil? || opts.empty?
          any_multi = true
          idx = edges.size
          edges << Edge.new(from: i, to: i + len, romaji_options: opts, kana: substr, skip: false)
          edges_by_node[i] << idx
        end

        # Skip edge only when this character has no single-char entry AND
        # no multi-char match starts here.
        if (opts1.nil? || opts1.empty?) && !any_multi
          idx = edges.size
          edges << Edge.new(from: i, to: i + 1, romaji_options: [], kana: ch, skip: true)
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
