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

  describe "#look" do
    it "queues a look action with no attributes" do
      bot = build_bot

      bot.look

      _(bot.actions).must_equal [{ type: :look, attributes: [] }]
    end

    it "queues a look action with single attribute" do
      bot = build_bot

      bot.look(:size)

      _(bot.actions).must_equal [{ type: :look, attributes: [:size] }]
    end

    it "queues a look action with multiple attributes" do
      bot = build_bot

      bot.look(:size, :velocity, :health)

      _(bot.actions).must_equal [{ type: :look, attributes: [:size, :velocity, :health] }]
    end

    it "raises ArgumentError for invalid attributes" do
      bot = build_bot

      _ { bot.look(:invalid) }.must_raise ArgumentError
    end

    it "accepts all valid attributes" do
      bot = build_bot

      bot.look(:size, :velocity, :shield, :health, :energy)

      _(bot.actions.first[:attributes]).must_equal [:size, :velocity, :shield, :health, :energy]
    end
  end
end
