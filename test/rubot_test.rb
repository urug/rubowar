# frozen_string_literal: true

require "test_helper"

class TestBot
  include Rubowar::Rubot
  def tick; end
end

class SmallBot
  include Rubowar::Rubot
  size :small
  def tick; end
end

class LargeBot
  include Rubowar::Rubot
  size :large
  def tick; end
end

def build_bot(energy: 50, health: 100)
  bot = TestBot.new
  bot.rubot_state = Rubowar::RubotState.new(
    x: 100.0, y: 200.0,
    velocity_x: 1.0, velocity_y: 2.0,
    speed: Math.sqrt(5),
    turret_angle: 90.0,
    health: health, energy: energy, shield_level: 10,
    damage_dealt: 25, damage_taken: 20,
    size: :medium
  )
  bot.arena_state = Rubowar::ArenaState.new
  bot.actions = []
  bot
end

describe Rubowar::Rubot do
  describe "size class method" do
    it "defaults to medium" do
      _(TestBot.size).must_equal :medium
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

      _(bot.arena_width).must_equal 800
    end

    it "delegates arena_height with default" do
      bot = build_bot

      _(bot.arena_height).must_equal 600
    end

    it "delegates friction with default" do
      bot = build_bot

      _(bot.friction).must_equal 0.95
    end
  end

  describe "#thrust" do
    it "queues a thrust action with speed and angle" do
      bot = build_bot

      bot.thrust(speed: 5, angle: 45)

      _(bot.actions).must_equal [{ type: :thrust, speed: 5, angle: 45 }]
    end

    it "normalizes angle to 0-360" do
      bot = build_bot

      bot.thrust(speed: 5, angle: 400)

      _(bot.actions.first[:angle]).must_equal 40
    end

    it "ignores zero speed" do
      bot = build_bot

      bot.thrust(speed: 0, angle: 45)

      _(bot.actions).must_be_empty
    end

    it "ignores negative speed" do
      bot = build_bot

      bot.thrust(speed: -5, angle: 45)

      _(bot.actions).must_be_empty
    end
  end

  describe "#turret" do
    it "queues a turret action with degrees" do
      bot = build_bot

      bot.turret(30)

      _(bot.actions).must_equal [{ type: :turret, degrees: 30 }]
    end

    it "normalizes degrees like turn" do
      bot = build_bot

      bot.turret(400)

      _(bot.actions.first[:degrees]).must_equal 40
    end
  end

  describe "#fire" do
    it "queues a fire action with energy" do
      bot = build_bot

      bot.fire(15)

      _(bot.actions).must_equal [{ type: :fire, energy: 15 }]
    end

    it "ignores zero energy" do
      bot = build_bot

      bot.fire(0)

      _(bot.actions).must_be_empty
    end
  end

  describe "#shield" do
    it "queues a shield action with energy" do
      bot = build_bot

      bot.shield(20)

      _(bot.actions).must_equal [{ type: :shield, energy: 20 }]
    end
  end

  describe "#probe" do
    it "queues a probe action defaulting to size when no attributes given" do
      bot = build_bot

      bot.probe

      _(bot.actions).must_equal [{ type: :probe, attributes: [:size] }]
    end

    it "queues a probe action with single attribute" do
      bot = build_bot

      bot.probe(:position)

      _(bot.actions).must_equal [{ type: :probe, attributes: [:position] }]
    end

    it "queues a probe action with multiple attributes" do
      bot = build_bot

      bot.probe(:position, :velocity, :health)

      _(bot.actions).must_equal [{ type: :probe, attributes: [:position, :velocity, :health] }]
    end

    it "raises ArgumentError for invalid attributes" do
      bot = build_bot

      _ { bot.probe(:invalid) }.must_raise ArgumentError
    end

    it "accepts all valid attributes" do
      bot = build_bot

      bot.probe(:size, :position, :velocity, :shield, :health, :energy)

      _(bot.actions.first[:attributes]).must_equal [:size, :position, :velocity, :shield, :health, :energy]
    end
  end

  describe "#scan" do
    it "queues a scan action with angle and distance" do
      bot = build_bot

      bot.scan(angle: 30, distance: 200)

      _(bot.actions).must_equal [{ type: :scan, angle: 30, distance: 200, velocity: false, owner: false }]
    end

    it "queues a scan action with velocity option" do
      bot = build_bot

      bot.scan(angle: 30, distance: 200, velocity: true)

      _(bot.actions).must_equal [{ type: :scan, angle: 30, distance: 200, velocity: true, owner: false }]
    end

    it "queues a scan action with owner option" do
      bot = build_bot

      bot.scan(angle: 30, distance: 200, owner: true)

      _(bot.actions).must_equal [{ type: :scan, angle: 30, distance: 200, velocity: false, owner: true }]
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
      _(bot.actions).must_be_empty
    end

    it "scan_result returns previous tick result" do
      bot = build_bot
      bot.scan_result = [{ x: 100, y: 200, type: :rubot }]

      _(bot.scan_result).must_equal [{ x: 100, y: 200, type: :rubot }]
    end

    it "raises ArgumentError for zero angle" do
      bot = build_bot

      _ { bot.scan(angle: 0, distance: 200) }.must_raise ArgumentError
    end

    it "raises ArgumentError for negative angle" do
      bot = build_bot

      _ { bot.scan(angle: -10, distance: 200) }.must_raise ArgumentError
    end

    it "raises ArgumentError for zero distance" do
      bot = build_bot

      _ { bot.scan(angle: 30, distance: 0) }.must_raise ArgumentError
    end

    it "raises ArgumentError for negative distance" do
      bot = build_bot

      _ { bot.scan(angle: 30, distance: -100) }.must_raise ArgumentError
    end
  end

  describe "#pulse" do
    it "queues a pulse action with distance" do
      bot = build_bot

      bot.pulse(distance: 100)

      _(bot.actions).must_equal [{ type: :pulse, distance: 100, owner: false }]
    end

    it "queues a pulse action with owner option" do
      bot = build_bot

      bot.pulse(distance: 100, owner: true)

      _(bot.actions).must_equal [{ type: :pulse, distance: 100, owner: true }]
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
      _(bot.actions).must_be_empty
    end

    it "pulse_result returns previous tick result" do
      bot = build_bot
      bot.pulse_result = [{ x: 150, y: 250, type: :rubot }]

      _(bot.pulse_result).must_equal [{ x: 150, y: 250, type: :rubot }]
    end

    it "raises ArgumentError for zero distance" do
      bot = build_bot

      _ { bot.pulse(distance: 0) }.must_raise ArgumentError
    end

    it "raises ArgumentError for negative distance" do
      bot = build_bot

      _ { bot.pulse(distance: -50) }.must_raise ArgumentError
    end
  end
end
