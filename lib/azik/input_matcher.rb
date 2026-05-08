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
