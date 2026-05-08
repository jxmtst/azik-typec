require 'minitest/autorun'
require 'azik/input_matcher'
require 'azik/decomposer'

class TestInputMatcher < Minitest::Test
  def setup
    @dec = Azik::Decomposer.new(Azik::Entries.load)
  end

  def test_single_ka_complete
    dag = @dec.decompose('か')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'a')
  end

  def test_miss_restores_cursors
    dag = @dec.decompose('か')
    state = Azik::InputMatcher.create(dag)
    Azik::InputMatcher.feed(state, dag, 'k')
    before = Marshal.dump(state.cursors)
    assert_equal :error, Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal before, Marshal.dump(state.cursors)
    assert_equal 1, state.miss_count
    assert_equal 2, state.total_keystrokes
  end

  def test_recover_after_miss
    dag = @dec.decompose('か')
    state = Azik::InputMatcher.create(dag)
    Azik::InputMatcher.feed(state, dag, 'k')
    Azik::InputMatcher.feed(state, dag, 'x')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'a')
  end

  def test_compound_shortcut_kt
    dag = @dec.decompose('こと')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 't')
  end

  def test_compound_rejects_non_shortest
    dag = @dec.decompose('こと')
    state = Azik::InputMatcher.create(dag)
    Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal :error, Azik::InputMatcher.feed(state, dag, 'o')
  end

  def test_total_keystrokes_counts_misses
    dag = @dec.decompose('あ')
    state = Azik::InputMatcher.create(dag)
    Azik::InputMatcher.feed(state, dag, 'x')
    Azik::InputMatcher.feed(state, dag, 'a')
    assert_equal 2, state.total_keystrokes
    assert_equal 1, state.miss_count
  end

  def test_epsilon_auto_skip
    dag = @dec.decompose('あ字い')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'a')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'i')
  end

  def test_uppercase_input_accepted
    dag = @dec.decompose('か')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'K')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'A')
  end

  def test_tenki_shortest_only
    dag = @dec.decompose('てんき')
    state = Azik::InputMatcher.create(dag)
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 't')
    assert_equal :error,    Azik::InputMatcher.feed(state, dag, 'e')
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'd')
    assert_equal :progress, Azik::InputMatcher.feed(state, dag, 'k')
    assert_equal :complete, Azik::InputMatcher.feed(state, dag, 'i')
  end

  def test_empty_dag
    dag = @dec.decompose('')
    state = Azik::InputMatcher.create(dag)
    assert_empty state.cursors
  end
end
