# frozen_string_literal: true

require "test_helper"

class TargetingTestBot
  include Rubowar::Rubot
  include Rubowar::SimpleTargeting

  size :medium

  def act; end
end

class CustomConfigTargetingBot
  include Rubowar::Rubot
  include Rubowar::SimpleTargeting

  size :medium

  TARGETING_CONFIG = {
    bullet_speed: 20,
    max_lead_chronons: 10,
    alignment_tolerance: 10,
    target_timeout: 50
  }.freeze

  def act; end
end

def build_targeting_state(health: 100, energy: 100, x: 100, y: 100, turret_angle: 0)
  Rubowar::RubotState.new(
    x:, y:,
    velocity_x: 0, velocity_y: 0, speed: 0,
    turret_angle:,
    health:, energy:, shield_level: 0,
    damage_dealt: 0, damage_taken: 0, size: :medium
  )
end

def build_targeting_arena(chronons: 1)
  Rubowar::ArenaState.new(
    arena_width: 800, arena_height: 600,
    friction: 0.95, chronons:,
    energons: [], live_rubot_count: 2,
    energon_spawn_interval: 80, energon_growth_rate: 1.0
  )
end

describe Rubowar::SimpleTargeting do
  describe "target acquisition" do
    it "acquires target from pulse results" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      target = bot.acquire_target_from_pulse([{ type: :rubot, x: 300, y: 200 }])

      _(target).wont_be_nil
      _(target[:x]).must_equal 300
      _(target[:y]).must_equal 200
    end

    it "acquires target from scan results with velocity" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      target = bot.acquire_target_from_scan([{ type: :rubot, x: 300, y: 200, velocity_x: 5, velocity_y: -3 }])

      _(target).wont_be_nil
      _(target[:velocity_x]).must_equal 5
      _(target[:velocity_y]).must_equal(-3)
    end

    it "acquires target from probe results" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      target = bot.acquire_target_from_probe({ x: 300, y: 200, velocity_x: 2, velocity_y: 1 })

      _(target).wont_be_nil
      _(target[:x]).must_equal 300
    end

    it "returns nil when no pulse results" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      target = bot.acquire_target_from_pulse(nil)

      _(target).must_be_nil
    end

    it "ignores bullets in pulse results" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      target = bot.acquire_target_from_pulse([{ type: :bullet, x: 300, y: 200 }])

      _(target).must_be_nil
    end

    it "acquires closest target when multiple present" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100)
      bot.arena_state = build_targeting_arena

      target = bot.acquire_target_from_pulse([
                                               { type: :rubot, x: 500, y: 500 },
                                               { type: :rubot, x: 200, y: 150 }
                                             ])

      _(target[:x]).must_equal 200
      _(target[:y]).must_equal 150
    end

    it "chains acquisition with || operator" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      # Probe returns nil, pulse returns target
      target = bot.acquire_target_from_probe(nil) || bot.acquire_target_from_pulse([{ type: :rubot, x: 300, y: 200 }])

      _(target[:x]).must_equal 300
    end
  end

  describe "target state" do
    it "stores target via attr_accessor" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      bot.target = { x: 300, y: 200 }

      _(bot.target[:x]).must_equal 300
    end

    it "calculates distance to target" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100)
      bot.arena_state = build_targeting_arena

      distance = bot.distance_to_target({ x: 200, y: 100 })

      _(distance).must_equal 100
    end

    it "tracks target age via target_chronon" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena(chronons: 10)
      bot.target_chronon = 10

      _(bot.target_age).must_equal 0

      bot.arena_state = build_targeting_arena(chronons: 15)
      _(bot.target_age).must_equal 5
    end

    it "marks target as stale after timeout" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena(chronons: 10)
      bot.target_chronon = 10

      _(bot.target_stale?).must_equal false

      bot.arena_state = build_targeting_arena(chronons: 50)
      _(bot.target_stale?).must_equal true
    end
  end

  describe "aiming" do
    it "calculates aim angle for stationary target" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100, turret_angle: 0)
      bot.arena_state = build_targeting_arena

      angle = bot.aim_at_target({ x: 200, y: 100, velocity_x: 0, velocity_y: 0 })

      _(angle).must_be_close_to 0, 0.1
    end

    it "clamps aim angle to max turn rate" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100, turret_angle: 0)
      bot.arena_state = build_targeting_arena

      # Target is north (90 degrees), max turn is 20
      angle = bot.aim_at_target({ x: 100, y: 200, velocity_x: 0, velocity_y: 0 })

      _(angle).must_equal 20
    end

    it "calculates lead position for moving target" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100)
      bot.arena_state = build_targeting_arena

      lead_x, lead_y = bot.lead_position_for({ x: 250, y: 100, velocity_x: 0, velocity_y: 10 })

      _(lead_x).must_equal 250
      _(lead_y).must_be :>, 100
    end

    it "checks turret alignment" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100, turret_angle: 0)
      bot.arena_state = build_targeting_arena

      _(bot.turret_aligned?({ x: 200, y: 100 })).must_equal true
      _(bot.turret_aligned?({ x: 100, y: 200 })).must_equal false
    end

    it "respects custom alignment tolerance" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100, turret_angle: 0)
      bot.arena_state = build_targeting_arena
      target = { x: 150, y: 130 }

      _(bot.turret_aligned?(target, tolerance: 5)).must_equal false
      _(bot.turret_aligned?(target, tolerance: 45)).must_equal true
    end

    it "returns 0 for nil target" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      _(bot.aim_at_target(nil)).must_equal 0
    end

    it "returns false for nil target alignment" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      _(bot.turret_aligned?(nil)).must_equal false
    end
  end

  describe "custom configuration" do
    it "uses custom config values" do
      bot = CustomConfigTargetingBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      _(bot.targeting_config(:bullet_speed)).must_equal 20
      _(bot.targeting_config(:target_timeout)).must_equal 50
    end

    it "falls back to defaults for unset values" do
      bot = CustomConfigTargetingBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena

      _(bot.targeting_config(:max_turret_turn)).must_equal 20
    end
  end
end
