module Azik
  Edge = Struct.new(:from, :to, :romaji_options, :kana, :skip, keyword_init: true) do
    def skip?; skip; end
  end

  Dag = Struct.new(:node_count, :edges, :edges_by_node, keyword_init: true)
end
