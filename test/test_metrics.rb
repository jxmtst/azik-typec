require 'minitest/autorun'
require 'azik/metrics'

class TestMetrics < Minitest::Test
  def test_basic_kpm
    m = Azik::Metrics.new(total_keystrokes: 60, miss_count: 0, elapsed_ms: 60_000)
    assert_in_delta 60.0, m.kpm, 0.01
    assert_in_delta 1.0, m.accuracy, 0.01
    assert_in_delta 60.0, m.effective_kpm, 0.01
  end

  def test_accuracy_with_misses
    m = Azik::Metrics.new(total_keystrokes: 100, miss_count: 10, elapsed_ms: 60_000)
    assert_in_delta 0.9, m.accuracy, 0.001
    assert_in_delta 90.0, m.effective_kpm, 0.1
  end

  def test_zero_keystrokes
    m = Azik::Metrics.new(total_keystrokes: 0, miss_count: 0, elapsed_ms: 1000)
    assert_equal 0.0, m.kpm
    assert_equal 1.0, m.accuracy
  end

  def test_accumulator
    acc = Azik::MetricsAccumulator.new
    acc.update(total_keystrokes: 10, miss_count: 1, elapsed_ms: 10_000)
    acc.commit
    acc.update(total_keystrokes: 5, miss_count: 0, elapsed_ms: 15_000)
    m = acc.current
    assert_equal 15, m.total_keystrokes
    assert_equal 1, m.miss_count
    assert_equal 15_000, m.elapsed_ms
  end
end
