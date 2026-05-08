require 'minitest/autorun'
require 'azik/decomposer'

class TestDecomposer < Minitest::Test
  def setup
    @entries = Azik::Entries.load
    @dec = Azik::Decomposer.new(@entries)
  end

  def test_single_kana_dag
    dag = @dec.decompose('か')
    assert_equal 2, dag.node_count
    assert_equal 1, dag.edges.size
    assert_includes dag.edges[0].romaji_options, 'ka'
    assert_equal 'か', dag.edges[0].kana
  end

  def test_non_target_char_becomes_skip_edge
    dag = @dec.decompose('あ字か')
    skip_edges = dag.edges.select(&:skip?)
    assert_equal 1, skip_edges.size
    assert_equal '字', skip_edges[0].kana
  end

  def test_punctuation_is_input_target
    dag = @dec.decompose('あ。')
    period = dag.edges.find { |e| e.kana == '。' }
    refute_nil period
    refute period.skip?
    assert_includes period.romaji_options, '.'
  end

  def test_empty_string
    dag = @dec.decompose('')
    assert_equal 1, dag.node_count
    assert_empty dag.edges
  end

  def test_shortest_only_for_single_kana
    dag = @dec.decompose('ん')
    edge = dag.edges[0]
    assert_includes edge.romaji_options, 'q'
    refute_includes edge.romaji_options, 'nn'
  end

end
