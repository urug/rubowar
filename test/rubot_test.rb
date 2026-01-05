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
    body_angle: 45.0, turret_angle: 90.0,
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
    it "queues a thrust action with energy" do
      bot = build_bot

      bot.thrust(10)

      _(bot.actions).must_equal [{ type: :thrust, energy: 10 }]
    end

    it "ignores zero energy" do
      bot = build_bot

      bot.thrust(0)

      _(bot.actions).must_be_empty
    end

    it "ignores negative energy" do
      bot = build_bot

      bot.thrust(-5)

      _(bot.actions).must_be_empty
    end
  end

  describe "#turn" do
    it "queues a turn action with degrees" do
      bot = build_bot

      bot.turn(45)

      _(bot.actions).must_equal [{ type: :turn, degrees: 45 }]
    end

    it "normalizes 370 degrees to 10" do
      bot = build_bot

      bot.turn(370)

      _(bot.actions.first[:degrees]).must_equal 10
    end

    it "normalizes -270 degrees to 90" do
      bot = build_bot

      bot.turn(-270)

      _(bot.actions.first[:degrees]).must_equal 90
    end

    it "ignores zero degrees" do
      bot = build_bot

      bot.turn(0)

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
    it "queues a look action with energy level" do
      bot = build_bot

      bot.look(3)

      _(bot.actions).must_equal [{ type: :look, energy: 3 }]
    end

    it "clamps energy to max of 5" do
      bot = build_bot

      bot.look(10)

      _(bot.actions.first[:energy]).must_equal 5
    end

    it "clamps energy to min of 1" do
      bot = build_bot

      bot.look(-5)

      _(bot.actions.first[:energy]).must_equal 1
    end
  end
end
