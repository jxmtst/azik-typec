require 'minitest/autorun'
require 'azik/decomposer'
require 'azik/input_matcher'
require 'tmpdir'
ENV['XDG_DATA_HOME'] = Dir.mktmpdir('azik-test-')

class TestSmoke < Minitest::Test
  def setup
    @dec = Azik::Decomposer.new(Azik::Entries.load)
  end

  def test_sentence_completion
    text = 'あいうえお'
    dag = @dec.decompose(text)
    state = Azik::InputMatcher.create(dag)
    result = nil
    'aiueo'.each_char { |c| result = Azik::InputMatcher.feed(state, dag, c) }
    assert_equal :complete, result
    assert_equal 0, state.miss_count
  end

  def test_azik_shortcut_sentence
    text = 'てんき'
    dag = @dec.decompose(text)
    state = Azik::InputMatcher.create(dag)
    result = nil
    'tdki'.each_char { |c| result = Azik::InputMatcher.feed(state, dag, c) }
    assert_equal :complete, result
  end
end
