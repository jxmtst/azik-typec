require 'azik/decomposer'
require 'azik/sentences'

module Azik
  class DrillSession
    Question = Struct.new(:kana, :dag, keyword_init: true)

    attr_reader :questions
    attr_accessor :current_index

    def initialize(entries:, decomposer:, count:, rng: Random.new)
      unique_kanas = entries.entries.map(&:kana).uniq
      picked = unique_kanas.shuffle(random: rng).first([count, unique_kanas.size].min)
      @questions = picked.map { |k| Question.new(kana: k, dag: decomposer.decompose(k)) }
      @current_index = 0
    end

    def current
      @questions[@current_index]
    end

    def advance
      @current_index += 1
    end

    def finished?
      @current_index >= @questions.size
    end
  end

  class SentenceSession
    Question = Struct.new(:text, :dag, keyword_init: true)

    attr_reader :time_limit_ms, :current_question

    def initialize(decomposer:, time_limit_sec:, sentences: Azik::SENTENCES, rng: Random.new)
      @decomposer = decomposer
      @time_limit_ms = time_limit_sec * 1000
      @pool = sentences.dup
      @rng = rng
      @shuffled = @pool.shuffle(random: @rng)
      @index = 0
      @current_question = nil
    end

    def next_question
      if @index >= @shuffled.size
        @shuffled = @pool.shuffle(random: @rng)
        @index = 0
      end
      text = @shuffled[@index]
      @index += 1
      @current_question = Question.new(text: text, dag: @decomposer.decompose(text))
      @current_question
    end
  end
end
