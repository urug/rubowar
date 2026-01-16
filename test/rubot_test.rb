# frozen_string_literal: true

require "test_helper"

# Shortcuts for Config constants used in tests
ARENA_WIDTH = Rubowar::Config::Arena::DEFAULT_WIDTH
ARENA_HEIGHT = Rubowar::Config::Arena::DEFAULT_HEIGHT
ARENA_FRICTION = Rubowar::Config::Arena::DEFAULT_FRICTION

class RubotTestBot
  include Rubowar::Rubot

  def act; end
end

class SmallBot
  include Rubowar::Rubot

  size :small
  def act; end
end

class LargeBot
  include Rubowar::Rubot

  size :large
  def act; end
end

def build_bot(energy: 50, health: 100, x: 100.0, y: 200.0, velocity_x: 1.0, velocity_y: 2.0, turret_angle: 90.0)
  bot = RubotTestBot.new
  speed = Math.sqrt((velocity_x**2) + (velocity_y**2))
  bot.rubot_state = Rubowar::RubotState.new(
    x:, y:,
    velocity_x:, velocity_y:,
    speed:,
    turret_angle:,
    health:, energy:, shield_level: 10,
    damage_dealt: 25, damage_taken: 20,
    size: :medium
  )
  bot.arena_state = Rubowar::ArenaState.new
  bot.actions = { sense: [], move: [], combat: [] }
  bot
end

describe Rubowar::Rubot do
  describe "size class method" do
    it "defaults to medium" do
      _(RubotTestBot.size).must_equal :medium
    end

    it "can be set to small" do
      _(SmallBot.size).must_equal :small
    end

    it "can be set to large" do
      _(LargeBot.size).must_equal :large
    end
  end

  describe "rubot state delegation" do
    it "delegates x position" do
      bot = build_bot

      _(bot.x).must_equal 100.0
    end

    it "delegates y position" do
      bot = build_bot

      _(bot.y).must_equal 200.0
    end

    it "delegates health" do
      bot = build_bot(health: 80)

      _(bot.health).must_equal 80
    end

    it "delegates energy" do
      bot = build_bot(energy: 75)

      _(bot.energy).must_equal 75
    end
  end

  describe "arena state delegation" do
    it "delegates arena_width with default" do
      bot = build_bot

      _(bot.arena_width).must_equal ARENA_WIDTH
    end

    it "delegates arena_height with default" do
      bot = build_bot

      _(bot.arena_height).must_equal ARENA_HEIGHT
    end

    it "delegates friction with default" do
      bot = build_bot

      _(bot.friction).must_equal ARENA_FRICTION
    end
  end

  describe "#thrust" do
    it "queues a thrust action with speed and angle" do
      bot = build_bot

      bot.thrust(speed: 5, angle: 45)

      _(bot.actions[:move]).must_equal [{ type: :thrust, speed: 5, angle: 45 }]
    end

    it "normalizes angle to 0-360" do
      bot = build_bot

      bot.thrust(speed: 5, angle: 400)

      _(bot.actions[:move].first[:angle]).must_equal 40
    end
  end

  describe "#rotate_turret" do
    it "queues a turret action with degrees" do
      bot = build_bot

      bot.rotate_turret(30)

      _(bot.actions[:move]).must_equal [{ type: :rotate_turret, degrees: 30 }]
    end

    it "normalizes degrees like turn" do
      bot = build_bot

      bot.rotate_turret(400)

      _(bot.actions[:move].first[:degrees]).must_equal 40
    end

    it "returns false when degrees is zero" do
      bot = build_bot

      result = bot.rotate_turret(0)

      _(result).must_equal false
      _(bot.actions[:move]).must_be_empty
    end

    it "returns false when degrees normalizes to zero" do
      bot = build_bot

      result = bot.rotate_turret(360)

      _(result).must_equal false
      _(bot.actions[:move]).must_be_empty
    end
  end

  describe "#fire" do
    it "queues a fire action with energy" do
      bot = build_bot

      bot.fire(15)

      _(bot.actions[:combat]).must_equal [{ type: :fire, energy: 15 }]
    end
  end

  describe "#raise_shields" do
    it "queues a shield action with energy" do
      bot = build_bot

      bot.raise_shields(20)

      _(bot.actions[:combat]).must_equal [{ type: :shield, energy: 20 }]
    end
  end

  describe "#probe" do
    it "queues a probe action defaulting to size when no attributes given" do
      bot = build_bot

      bot.probe

      _(bot.actions[:sense]).must_equal [{ type: :probe, attributes: [:size] }]
    end

    it "queues a probe action with single attribute" do
      bot = build_bot

      bot.probe(:position)

      _(bot.actions[:sense]).must_equal [{ type: :probe, attributes: [:position] }]
    end

    it "queues a probe action with multiple attributes" do
      bot = build_bot

      bot.probe(:position, :velocity, :health)

      _(bot.actions[:sense]).must_equal [{ type: :probe, attributes: %i[position velocity health] }]
    end

    it "raises ArgumentError for invalid attributes" do
      bot = build_bot

      _ { bot.probe(:invalid) }.must_raise ArgumentError
    end

    it "accepts all valid attributes" do
      bot = build_bot

      bot.probe(:size, :position, :velocity, :shield, :health, :energy)

      _(bot.actions[:sense].first[:attributes]).must_equal %i[size position velocity shield health energy]
    end

    it "removes duplicate attributes" do
      bot = build_bot

      bot.probe(:size, :size, :position, :size)

      _(bot.actions[:sense].first[:attributes]).must_equal %i[size position]
    end

    it "only charges energy once for duplicate attributes" do
      bot = build_bot(energy: 50)
      bot._pending_energy_spend = 0

      # size costs 1 energy, position costs 4 energy
      # With duplicates removed, total should be 5, not 6
      bot.probe(:size, :size, :position)

      # pending energy should reflect deduplicated cost
      _(bot._pending_energy_spend).must_equal 5
    end
  end

  describe "#scan" do
    it "queues a scan action with angle and distance" do
      bot = build_bot

      bot.scan(angle: 30, distance: 200)

      _(bot.actions[:sense]).must_equal [{ type: :scan, angle: 30, distance: 200, velocity: false, owner: false }]
    end

    it "queues a scan action with velocity option" do
      bot = build_bot

      bot.scan(angle: 30, distance: 200, velocity: true)

      _(bot.actions[:sense]).must_equal [{ type: :scan, angle: 30, distance: 200, velocity: true, owner: false }]
    end

    it "queues a scan action with owner option" do
      bot = build_bot

      bot.scan(angle: 30, distance: 200, owner: true)

      _(bot.actions[:sense]).must_equal [{ type: :scan, angle: 30, distance: 200, velocity: false, owner: true }]
    end

    it "returns true when enough energy" do
      bot = build_bot

      result = bot.scan(angle: 30, distance: 200)

      _(result).must_equal true
    end

    it "returns false when insufficient energy" do
      bot = build_bot(energy: 1)

      result = bot.scan(angle: 30, distance: 200)

      _(result).must_equal false
      _(bot.actions[:sense]).must_be_empty
    end

    it "scan_echo returns previous tick result" do
      bot = build_bot
      bot.scan_echo = [{ x: 100, y: 200, type: :rubot }]

      _(bot.scan_echo).must_equal [{ x: 100, y: 200, type: :rubot }]
    end
  end

  describe "#pulse" do
    it "queues a pulse action with distance" do
      bot = build_bot

      bot.pulse(distance: 100)

      _(bot.actions[:sense]).must_equal [{ type: :pulse, distance: 100, owner: false }]
    end

    it "queues a pulse action with owner option" do
      bot = build_bot

      bot.pulse(distance: 100, owner: true)

      _(bot.actions[:sense]).must_equal [{ type: :pulse, distance: 100, owner: true }]
    end

    it "returns true when enough energy" do
      bot = build_bot

      result = bot.pulse(distance: 100)

      _(result).must_equal true
    end

    it "returns false when insufficient energy" do
      bot = build_bot(energy: 1)

      result = bot.pulse(distance: 100)

      _(result).must_equal false
      _(bot.actions[:sense]).must_be_empty
    end

    it "pulse_echo returns previous tick result" do
      bot = build_bot
      bot.pulse_echo = [{ x: 150, y: 250, type: :rubot }]

      _(bot.pulse_echo).must_equal [{ x: 150, y: 250, type: :rubot }]
    end
  end

  describe "#detect" do
    it "queues a detect action" do
      bot = build_bot

      bot.detect

      _(bot.actions[:sense]).must_equal [{ type: :detect }]
    end

    it "returns true when enough energy" do
      bot = build_bot

      result = bot.detect

      _(result).must_equal true
    end

    it "returns false when insufficient energy" do
      bot = build_bot(energy: 1)

      result = bot.detect

      _(result).must_equal false
      _(bot.actions[:sense]).must_be_empty
    end

    it "detect_intel returns previous tick result" do
      bot = build_bot
      bot.detect_intel = { probed: 1, scanned: 2, pulsed: 0 }

      _(bot.detect_intel).must_equal({ probed: 1, scanned: 2, pulsed: 0 })
    end
  end

  describe "#distance_to" do
    it "calculates distance to a point" do
      bot = build_bot(x: 0.0, y: 0.0)

      result = bot.distance_to(target_x: 3.0, target_y: 4.0)

      _(result).must_equal 5.0
    end

    it "returns zero for same position" do
      bot = build_bot(x: 100.0, y: 200.0)

      result = bot.distance_to(target_x: 100.0, target_y: 200.0)

      _(result).must_equal 0.0
    end
  end

  describe "#angle_to" do
    it "returns 0 for point directly east" do
      bot = build_bot(x: 100.0, y: 100.0)

      result = bot.angle_to(target_x: 200.0, target_y: 100.0)

      _(result).must_equal 0.0
    end

    it "returns 90 for point directly north" do
      bot = build_bot(x: 100.0, y: 100.0)

      result = bot.angle_to(target_x: 100.0, target_y: 200.0)

      _(result).must_equal 90.0
    end

    it "returns 180 for point directly west" do
      bot = build_bot(x: 100.0, y: 100.0)

      result = bot.angle_to(target_x: 0.0, target_y: 100.0)

      _(result).must_equal 180.0
    end

    it "returns -90 for point directly south" do
      bot = build_bot(x: 100.0, y: 100.0)

      result = bot.angle_to(target_x: 100.0, target_y: 0.0)

      _(result).must_equal(-90.0)
    end

    it "returns 45 for point northeast" do
      bot = build_bot(x: 100.0, y: 100.0)

      result = bot.angle_to(target_x: 200.0, target_y: 200.0)

      _(result).must_equal 45.0
    end
  end

  describe "#normalize_angle" do
    it "keeps angle in -180..180 range" do
      bot = build_bot

      _(bot.normalize_angle(0)).must_equal 0
      _(bot.normalize_angle(90)).must_equal 90
      _(bot.normalize_angle(180)).must_equal 180
      _(bot.normalize_angle(-90)).must_equal(-90)
    end

    it "wraps angles above 180" do
      bot = build_bot

      _(bot.normalize_angle(270)).must_equal(-90)
      _(bot.normalize_angle(360)).must_equal 0
      _(bot.normalize_angle(450)).must_equal 90
    end

    it "wraps angles below -180" do
      bot = build_bot

      _(bot.normalize_angle(-270)).must_equal 90
      _(bot.normalize_angle(-360)).must_equal 0
    end
  end

  describe "#near_wall?" do
    it "returns true when near left wall" do
      bot = build_bot(x: 30.0, y: ARENA_HEIGHT / 2.0)

      _(bot.near_wall?(50)).must_equal true
    end

    it "returns true when near right wall" do
      bot = build_bot(x: ARENA_WIDTH - 30.0, y: ARENA_HEIGHT / 2.0)

      _(bot.near_wall?(50)).must_equal true
    end

    it "returns true when near bottom wall" do
      bot = build_bot(x: ARENA_WIDTH / 2.0, y: 30.0)

      _(bot.near_wall?(50)).must_equal true
    end

    it "returns true when near top wall" do
      bot = build_bot(x: ARENA_WIDTH / 2.0, y: ARENA_HEIGHT - 30.0)

      _(bot.near_wall?(50)).must_equal true
    end

    it "returns false when in center" do
      bot = build_bot(x: ARENA_WIDTH / 2.0, y: ARENA_HEIGHT / 2.0)

      _(bot.near_wall?(50)).must_equal false
    end
  end

  describe "#nearest_wall_distance" do
    it "returns distance to closest wall" do
      bot = build_bot(x: 30.0, y: 300.0)

      _(bot.nearest_wall_distance).must_equal 30.0
    end

    it "returns minimum of all wall distances" do
      bot = build_bot(x: 100.0, y: 50.0)

      _(bot.nearest_wall_distance).must_equal 50.0
    end
  end

  describe "#nearest_wall" do
    it "returns :left when closest to left wall" do
      bot = build_bot(x: 30.0, y: ARENA_HEIGHT / 2.0)

      _(bot.nearest_wall).must_equal :left
    end

    it "returns :right when closest to right wall" do
      bot = build_bot(x: ARENA_WIDTH - 30.0, y: ARENA_HEIGHT / 2.0)

      _(bot.nearest_wall).must_equal :right
    end

    it "returns :bottom when closest to bottom wall" do
      bot = build_bot(x: ARENA_WIDTH / 2.0, y: 30.0)

      _(bot.nearest_wall).must_equal :bottom
    end

    it "returns :top when closest to top wall" do
      bot = build_bot(x: ARENA_WIDTH / 2.0, y: ARENA_HEIGHT - 30.0)

      _(bot.nearest_wall).must_equal :top
    end
  end

  describe "#wall_distance" do
    it "returns distance to right wall when facing east" do
      bot = build_bot(x: 100.0, y: ARENA_HEIGHT / 2.0)

      result = bot.wall_distance(0)

      _(result).must_equal(ARENA_WIDTH - 100.0)
    end

    it "returns distance to top wall when facing north" do
      bot = build_bot(x: ARENA_WIDTH / 2.0, y: 100.0)

      result = bot.wall_distance(90)

      _(result).must_equal(ARENA_HEIGHT - 100.0)
    end

    it "returns distance to left wall when facing west" do
      bot = build_bot(x: 100.0, y: ARENA_HEIGHT / 2.0)

      result = bot.wall_distance(180)

      _(result).must_equal 100.0
    end

    it "returns distance to bottom wall when facing south" do
      bot = build_bot(x: ARENA_WIDTH / 2.0, y: 100.0)

      result = bot.wall_distance(270)

      _(result).must_equal 100.0
    end
  end

  describe "#velocity_angle" do
    it "returns angle of current velocity" do
      bot = build_bot(velocity_x: 5.0, velocity_y: 0.0)

      _(bot.velocity_angle).must_equal 0.0
    end

    it "returns 90 for northward velocity" do
      bot = build_bot(velocity_x: 0.0, velocity_y: 5.0)

      _(bot.velocity_angle).must_equal 90.0
    end

    it "returns nil when stationary" do
      bot = build_bot(velocity_x: 0.0, velocity_y: 0.0)

      _(bot.velocity_angle).must_be_nil
    end
  end

  describe "#approaching_wall?" do
    it "returns true when moving toward left wall" do
      bot = build_bot(x: 40.0, y: ARENA_HEIGHT / 2.0, velocity_x: -5.0, velocity_y: 0.0)

      _(bot.approaching_wall?(60)).must_equal true
    end

    it "returns true when moving toward right wall" do
      bot = build_bot(x: ARENA_WIDTH - 40.0, y: ARENA_HEIGHT / 2.0, velocity_x: 5.0, velocity_y: 0.0)

      _(bot.approaching_wall?(60)).must_equal true
    end

    it "returns false when stationary" do
      bot = build_bot(x: 40.0, y: ARENA_HEIGHT / 2.0, velocity_x: 0.0, velocity_y: 0.0)

      _(bot.approaching_wall?(60)).must_equal false
    end

    it "returns false when moving away from wall" do
      bot = build_bot(x: 40.0, y: ARENA_HEIGHT / 2.0, velocity_x: 5.0, velocity_y: 0.0)

      _(bot.approaching_wall?(60)).must_equal false
    end
  end

  describe "#momentum_aligned?" do
    it "returns true when velocity matches desired direction" do
      bot = build_bot(velocity_x: 5.0, velocity_y: 0.0)

      _(bot.momentum_aligned?(0, tolerance: 45)).must_equal true
    end

    it "returns true when within tolerance" do
      bot = build_bot(velocity_x: 5.0, velocity_y: 0.0)

      _(bot.momentum_aligned?(30, tolerance: 45)).must_equal true
    end

    it "returns false when outside tolerance" do
      bot = build_bot(velocity_x: 5.0, velocity_y: 0.0)

      _(bot.momentum_aligned?(90, tolerance: 45)).must_equal false
    end

    it "returns true when stationary" do
      bot = build_bot(velocity_x: 0.0, velocity_y: 0.0)

      _(bot.momentum_aligned?(90, tolerance: 45)).must_equal true
    end
  end

  describe "#arena_diagonal" do
    it "calculates arena diagonal length" do
      bot = build_bot

      result = bot.arena_diagonal

      expected = Math.sqrt((ARENA_WIDTH**2) + (ARENA_HEIGHT**2))
      _(result).must_equal expected
    end
  end

  describe "#speed_from_velocity" do
    it "calculates speed from components" do
      bot = build_bot

      result = bot.speed_from_velocity(velocity_x: 3.0, velocity_y: 4.0)

      _(result).must_equal 5.0
    end

    it "returns zero when velocity is nil" do
      bot = build_bot

      result = bot.speed_from_velocity(velocity_x: nil, velocity_y: nil)

      _(result).must_equal 0
    end
  end

  describe "#clamp_to_arena" do
    it "returns original coordinates when inside arena" do
      bot = build_bot

      result = bot.clamp_to_arena(target_x: ARENA_WIDTH / 2.0, target_y: ARENA_HEIGHT / 2.0)

      _(result).must_equal [ARENA_WIDTH / 2.0, ARENA_HEIGHT / 2.0]
    end

    it "clamps x to left boundary" do
      bot = build_bot

      result = bot.clamp_to_arena(target_x: -50.0, target_y: ARENA_HEIGHT / 2.0, margin: 20)

      _(result).must_equal [20.0, ARENA_HEIGHT / 2.0]
    end

    it "clamps x to right boundary" do
      bot = build_bot

      result = bot.clamp_to_arena(target_x: ARENA_WIDTH + 100.0, target_y: ARENA_HEIGHT / 2.0, margin: 20)

      _(result).must_equal [ARENA_WIDTH - 20.0, ARENA_HEIGHT / 2.0]
    end

    it "clamps y to bottom boundary" do
      bot = build_bot

      result = bot.clamp_to_arena(target_x: ARENA_WIDTH / 2.0, target_y: -50.0, margin: 20)

      _(result).must_equal [ARENA_WIDTH / 2.0, 20.0]
    end

    it "clamps y to top boundary" do
      bot = build_bot

      result = bot.clamp_to_arena(target_x: ARENA_WIDTH / 2.0, target_y: ARENA_HEIGHT + 100.0, margin: 20)

      _(result).must_equal [ARENA_WIDTH / 2.0, ARENA_HEIGHT - 20.0]
    end
  end

  describe "#lead_position" do
    it "returns target position when velocity is nil" do
      bot = build_bot(x: 0.0, y: 0.0)

      result = bot.lead_position(target_x: 100.0, target_y: 100.0, velocity_x: nil, velocity_y: nil)

      _(result).must_equal [100.0, 100.0]
    end

    it "returns position ahead of moving target" do
      bot = build_bot(x: 100.0, y: 300.0)

      result = bot.lead_position(target_x: 200.0, target_y: 300.0, velocity_x: 10.0, velocity_y: 0.0)

      # Target at 200,300 moving east at 10, distance is 100, projectile speed 18
      # Lead chronons = 100/18 = 5.55
      # Lead x = 200 + 10*5.55 = 255.5
      _(result[0]).must_be :>, 200.0
      _(result[1]).must_equal 300.0
    end

    it "clamps lead position to arena bounds" do
      bot = build_bot(x: 0.0, y: 0.0)

      result = bot.lead_position(target_x: ARENA_WIDTH - 40.0, target_y: 0.0, velocity_x: 100.0, velocity_y: 0.0)

      # Should clamp to arena width - 20
      _(result[0]).must_equal(ARENA_WIDTH - 20)
    end
  end

  describe "#lead_angle" do
    it "calculates angle to lead position" do
      bot = build_bot(x: 0.0, y: 0.0)

      result = bot.lead_angle(target_x: 100.0, target_y: 0.0, velocity_x: 0.0, velocity_y: 10.0)

      # Target moving north, so lead position is above target
      _(result).must_be :>, 0
    end
  end

  describe "#find_nearest_energon" do
    it "returns nil when no energons exist" do
      bot = build_bot
      bot.arena_state = Rubowar::ArenaState.new(energons: [])

      result = bot.find_nearest_energon

      _(result).must_be_nil
    end

    it "returns closest energon" do
      bot = build_bot(x: 100.0, y: 100.0)
      energons = [
        { x: 500.0, y: 500.0 },
        { x: 150.0, y: 100.0 },
        { x: 300.0, y: 300.0 }
      ]
      bot.arena_state = Rubowar::ArenaState.new(energons:)

      result = bot.find_nearest_energon

      _(result).must_equal({ x: 150.0, y: 100.0 })
    end

    it "respects max_distance filter" do
      bot = build_bot(x: 100.0, y: 100.0)
      energons = [
        { x: 500.0, y: 500.0 },
        { x: 150.0, y: 100.0 }
      ]
      bot.arena_state = Rubowar::ArenaState.new(energons:)

      result = bot.find_nearest_energon(max_distance: 40)

      _(result).must_be_nil
    end
  end

  describe "#energon_still_exists?" do
    it "returns true when energon exists at position" do
      bot = build_bot
      target = { x: 200.0, y: 300.0 }
      bot.arena_state = Rubowar::ArenaState.new(energons: [target])

      _(bot.energon_still_exists?(target)).must_equal true
    end

    it "returns false when energon no longer exists" do
      bot = build_bot
      target = { x: 200.0, y: 300.0 }
      bot.arena_state = Rubowar::ArenaState.new(energons: [])

      _(bot.energon_still_exists?(target)).must_equal false
    end

    it "returns false for nil target" do
      bot = build_bot

      _(bot.energon_still_exists?(nil)).must_equal false
    end
  end
end
