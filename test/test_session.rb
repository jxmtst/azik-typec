require 'minitest/autorun'
require 'azik/session'

class TestSession < Minitest::Test
  def setup
    @entries = Azik::Entries.load
    @decomposer = Azik::Decomposer.new(@entries)
  end

  def test_drill_session_generates_questions
    s = Azik::DrillSession.new(entries: @entries, decomposer: @decomposer, count: 5)
    assert_equal 5, s.questions.size
    assert_equal 0, s.current_index
    first = s.questions.first
    refute_nil first.dag
    assert_kind_of String, first.kana
  end

  def test_sentence_session_next_question
    s = Azik::SentenceSession.new(decomposer: @decomposer, time_limit_sec: 60, sentences: %w[あい うえ])
    q1 = s.next_question
    assert_includes %w[あい うえ], q1.text
    q2 = s.next_question
    refute_nil q2.dag
  end

  def test_sentence_session_wraps_around
    s = Azik::SentenceSession.new(decomposer: @decomposer, time_limit_sec: 60, sentences: ['あ'])
    2.times { s.next_question }
    assert_kind_of Azik::SentenceSession::Question, s.current_question
  end
end
