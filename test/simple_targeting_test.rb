# frozen_string_literal: true

require "test_helper"

class TargetingTestBot
  include Rubowar::Rubot
  include Rubowar::SimpleTargeting

  size :medium

  def tick; end
end

class CustomConfigTargetingBot
  include Rubowar::Rubot
  include Rubowar::SimpleTargeting

  size :medium

  TARGETING_CONFIG = {
    bullet_speed: 20,
    max_lead_ticks: 10,
    alignment_tolerance: 10,
    target_timeout: 50
  }.freeze

  def tick; end
end

def build_targeting_state(health: 100, energy: 100, x: 100, y: 100)
  Rubowar::RubotState.new(
    x:, y:,
    velocity_x: 0, velocity_y: 0, speed: 0,
    turret_angle: 0,
    health:, energy:, shield_level: 0,
    damage_dealt: 0, damage_taken: 0, size: :medium
  )
end

def build_targeting_arena(tick_number: 1)
  Rubowar::ArenaState.new(
    arena_width: 800, arena_height: 600,
    friction: 0.95, tick_number:,
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
      bot.pulse_result = [{ type: :rubot, x: 300, y: 200 }]

      result = bot.acquire_target_from_pulse

      _(result).must_equal true
      _(bot.target?).must_equal true
      _(bot.targeting_target[:x]).must_equal 300
      _(bot.targeting_target[:y]).must_equal 200
    end

    it "acquires target from scan results with velocity" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena
      bot.scan_result = [{ type: :rubot, x: 300, y: 200, velocity_x: 5, velocity_y: -3 }]

      result = bot.acquire_target_from_scan

      _(result).must_equal true
      _(bot.targeting_target[:velocity_x]).must_equal 5
      _(bot.targeting_target[:velocity_y]).must_equal(-3)
    end

    it "acquires target from probe results" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena
      bot.probe_result = { x: 300, y: 200, velocity_x: 2, velocity_y: 1 }

      result = bot.acquire_target_from_probe

      _(result).must_equal true
      _(bot.targeting_target[:x]).must_equal 300
    end

    it "returns false when no pulse results" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena
      bot.pulse_result = nil

      result = bot.acquire_target_from_pulse

      _(result).must_equal false
      _(bot.target?).must_equal false
    end

    it "ignores bullets in pulse results" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena
      bot.pulse_result = [{ type: :bullet, x: 300, y: 200 }]

      result = bot.acquire_target_from_pulse

      _(result).must_equal false
    end

    it "acquires closest target when multiple present" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100)
      bot.arena_state = build_targeting_arena
      bot.pulse_result = [
        { type: :rubot, x: 500, y: 500 },
        { type: :rubot, x: 200, y: 150 }
      ]

      bot.acquire_target_from_pulse

      _(bot.targeting_target[:x]).must_equal 200
      _(bot.targeting_target[:y]).must_equal 150
    end
  end

  describe "target state" do
    it "clears target" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena
      bot.pulse_result = [{ type: :rubot, x: 300, y: 200 }]
      bot.acquire_target_from_pulse

      bot.clear_target

      _(bot.target?).must_equal false
      _(bot.targeting_target).must_be_nil
    end

    it "calculates target distance" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100)
      bot.arena_state = build_targeting_arena
      bot.assign_target({ x: 200, y: 100 })

      _(bot.target_distance).must_equal 100
    end

    it "tracks target age" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena(tick_number: 10)
      bot.assign_target({ x: 200, y: 100 })

      _(bot.target_age).must_equal 0

      bot.arena_state = build_targeting_arena(tick_number: 15)
      _(bot.target_age).must_equal 5
    end

    it "marks target as stale after timeout" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state
      bot.arena_state = build_targeting_arena(tick_number: 10)
      bot.assign_target({ x: 200, y: 100 })

      _(bot.target_stale?).must_equal false

      bot.arena_state = build_targeting_arena(tick_number: 50)
      _(bot.target_stale?).must_equal true
      _(bot.target?).must_equal false
    end
  end

  describe "aiming" do
    it "calculates lead angle for stationary target" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100)
      bot.arena_state = build_targeting_arena
      bot.assign_target({ x: 200, y: 100, velocity_x: 0, velocity_y: 0 })

      angle = bot.target_lead_angle

      _(angle).must_be_close_to 0, 0.1
    end

    it "calculates lead position for moving target" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100)
      bot.arena_state = build_targeting_arena
      bot.assign_target({ x: 250, y: 100, velocity_x: 0, velocity_y: 10 })

      lead_x, lead_y = bot.target_lead_position

      _(lead_x).must_equal 250
      _(lead_y).must_be :>, 100
    end

    it "checks turret alignment" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100)
      bot.arena_state = build_targeting_arena
      bot.assign_target({ x: 200, y: 100 })

      _(bot.turret_aligned?).must_equal true

      bot.assign_target({ x: 100, y: 200 })
      _(bot.turret_aligned?).must_equal false
    end

    it "respects custom alignment tolerance" do
      bot = TargetingTestBot.new
      bot.rubot_state = build_targeting_state(x: 100, y: 100)
      bot.arena_state = build_targeting_arena
      bot.assign_target({ x: 150, y: 130 })

      _(bot.turret_aligned?(tolerance: 5)).must_equal false
      _(bot.turret_aligned?(tolerance: 45)).must_equal true
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
