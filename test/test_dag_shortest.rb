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

  def test_skip_edge_retained_on_path
    dag = @dec.decompose('あ字か')
    skip_edges = dag.edges.select(&:skip?)
    assert_equal 1, skip_edges.size
    assert(dag.edges_by_node[1].any? { |i| dag.edges[i].skip? })
  end
end
