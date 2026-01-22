# frozen_string_literal: true

require "test_helper"

describe Rubowar::BattleStats do
  def build_test_battle
    event_bus = Rubowar::EventBus.new(chronon_limit: 100)
    arena = Rubowar::Arena.new(width: 400, height: 400, friction: 0.98, event_bus:)
    battle = Rubowar::Battle.new(arena:, event_bus:, seed: 12345)

    # Register two bots
    battle.register(Rubowar::LocalActor.new(Rubowar::StationaryBot), position: { x: 100, y: 100 })
    battle.register(Rubowar::LocalActor.new(Rubowar::SpinnerBot), position: { x: 300, y: 300 })
    battle
  end

  describe "#stats" do
    it "returns a BattleStats object" do
      battle = build_test_battle
      battle.run

      stats = battle.stats

      assert_instance_of Rubowar::BattleStats, stats
    end

    it "provides chronon count" do
      battle = build_test_battle
      battle.run

      stats = battle.stats

      assert_kind_of Integer, stats.chronons
      assert stats.chronons.positive?
    end

    it "provides seed" do
      battle = build_test_battle
      battle.run

      stats = battle.stats

      assert_equal 12345, stats.seed
    end

    it "provides winner information" do
      battle = build_test_battle
      battle.run

      stats = battle.stats

      # SpinnerBot should win against StationaryBot
      refute_nil stats.winner
      refute_nil stats.winner_id
      assert_equal :victory, stats.outcome
    end

    it "provides total damage" do
      battle = build_test_battle
      battle.run

      stats = battle.stats

      assert_kind_of Numeric, stats.total_damage
    end

    it "provides alive and death counts" do
      battle = build_test_battle
      battle.run

      stats = battle.stats

      # At end, typically one alive and one dead
      assert_kind_of Integer, stats.alive_count
      assert_kind_of Integer, stats.death_count
      assert_equal 2, stats.alive_count + stats.death_count
    end
  end

  describe "#[bot_id]" do
    it "returns per-bot stats by ID" do
      battle = build_test_battle
      battle.run

      stats = battle.stats
      bot_id = stats.bot_ids.first
      bot_stats = stats[bot_id]

      refute_nil bot_stats
      assert_includes bot_stats.keys, :name
      assert_includes bot_stats.keys, :health
      assert_includes bot_stats.keys, :damage_dealt
      assert_includes bot_stats.keys, :damage_taken
      assert_includes bot_stats.keys, :alive
    end

    it "returns nil for unknown bot ID" do
      battle = build_test_battle
      battle.run

      stats = battle.stats

      assert_nil stats["unknown-id"]
    end

    it "includes position data" do
      battle = build_test_battle
      battle.run

      stats = battle.stats
      bot_id = stats.bot_ids.first
      bot_stats = stats[bot_id]

      assert_includes bot_stats.keys, :x
      assert_includes bot_stats.keys, :y
      assert_includes bot_stats.keys, :turret_angle
    end
  end

  describe "#bot_ids" do
    it "returns all bot IDs" do
      battle = build_test_battle
      battle.run

      stats = battle.stats

      assert_equal 2, stats.bot_ids.size
    end
  end

  describe "#each" do
    it "iterates over all bots" do
      battle = build_test_battle
      battle.run

      stats = battle.stats
      count = 0
      stats.each { |_id, _bot_stats| count += 1 }

      assert_equal 2, count
    end
  end

  describe "#to_h" do
    it "converts to a serializable hash" do
      battle = build_test_battle
      battle.run

      stats = battle.stats
      hash = stats.to_h

      assert_kind_of Hash, hash
      assert_includes hash.keys, :chronons
      assert_includes hash.keys, :seed
      assert_includes hash.keys, :winner
      assert_includes hash.keys, :outcome
      assert_includes hash.keys, :bots
    end
  end

  describe "#to_s" do
    it "provides human-readable output" do
      battle = build_test_battle
      battle.run

      stats = battle.stats
      output = stats.to_s

      assert_includes output, "Battle Stats"
      assert_includes output, "chronons"
      assert_includes output, "Outcome"
    end
  end
end
