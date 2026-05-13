require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'time'
require 'azik/score_record'
require 'azik/score_store'

class TestScoreStore < Minitest::Test
  def sample(t = Time.iso8601('2026-05-12T14:23:01+09:00'), eff: 298.1)
    Azik::ScoreRecord.new(
      timestamp: t, mode: :sentence,
      raw_kpm: 312.4, effective_kpm: eff, accuracy: 0.954,
      total_keystrokes: 312, miss_count: 15, elapsed_ms: 60_000
    )
  end

  def test_append_then_load_roundtrip
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'scores.jsonl')
      store = Azik::ScoreStore.new(path: path)
      store.append(sample)
      records = store.load_all
      assert_equal 1, records.size
      assert_in_delta 298.1, records.first.effective_kpm, 0.001
    end
  end

  def test_append_creates_parent_directory
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'a', 'b', 'scores.jsonl')
      store = Azik::ScoreStore.new(path: path)
      store.append(sample)
      assert File.exist?(path)
    end
  end

  def test_load_all_returns_empty_when_file_missing
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'absent.jsonl')
      store = Azik::ScoreStore.new(path: path)
      assert_equal [], store.load_all
    end
  end

  def test_load_all_skips_broken_lines
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'scores.jsonl')
      store = Azik::ScoreStore.new(path: path)
      store.append(sample(eff: 100.0))
      File.open(path, 'a') { |f| f.puts 'not-json' }
      File.open(path, 'a') { |f| f.puts '{"timestamp":"2026-05-12T14:23:01+09:00"}' } # missing keys
      store.append(sample(eff: 200.0))
      records = store.load_all
      assert_equal 2, records.size
      kpms = records.map(&:effective_kpm).sort
      assert_in_delta 100.0, kpms[0], 0.001
      assert_in_delta 200.0, kpms[1], 0.001
    end
  end

  def test_default_path_uses_xdg_data_home_when_set
    Dir.mktmpdir do |dir|
      ENV['XDG_DATA_HOME'] = dir
      path = Azik::ScoreStore.default_path
      assert_equal File.join(dir, 'azik-typec', 'scores.jsonl'), path
    ensure
      ENV.delete('XDG_DATA_HOME')
    end
  end

  def test_default_path_falls_back_to_local_share
    original = ENV['XDG_DATA_HOME']
    ENV.delete('XDG_DATA_HOME')
    path = Azik::ScoreStore.default_path
    assert path.end_with?(File.join('.local', 'share', 'azik-typec', 'scores.jsonl'))
  ensure
    ENV['XDG_DATA_HOME'] = original
  end
end
