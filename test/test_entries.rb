require 'minitest/autorun'
require 'azik/entries'

class TestEntries < Minitest::Test
  def setup
    @entries = Azik::Entries.load
  end

  def test_loads_basic_mappings
    ka = @entries.lookup_kana('か')
    refute_nil ka
    assert_includes ka.map(&:romaji), 'ka'
  end

  def test_loads_azik_shortcut
    n = @entries.lookup_kana('ん')
    assert_includes n.map(&:romaji), 'q'
  end

  def test_loads_compound_word
    koto = @entries.lookup_kana('こと')
    assert_includes koto.map(&:romaji), 'kt'
  end

  def test_shortest_romaji_for_kana
    assert_equal ['q'], @entries.shortest_romaji('ん')
  end

  def test_shortest_romaji_returns_all_equal_length
    result = @entries.shortest_romaji('き')
    assert_equal 2, result.size
    assert_includes result, 'ki'
    assert_includes result, 'kf'
  end

  def test_unknown_kana_returns_nil
    assert_nil @entries.lookup_kana('漢')
  end
end
