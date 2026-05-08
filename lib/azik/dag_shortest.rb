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
