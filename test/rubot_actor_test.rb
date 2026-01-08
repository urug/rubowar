# frozen_string_literal: true

require "test_helper"

class DummyBot
  include Rubowar::Rubot

  size :medium
  def act; end
end

class SmallDummyBot
  include Rubowar::Rubot

  size :small
  def act; end
end

class LargeDummyBot
  include Rubowar::Rubot

  size :large
  def act; end
end

describe Rubowar::RubotActor do
  describe "initialization" do
    it "starts with full health for its size" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.health).must_equal runner.max_health
    end

    it "starts with full energy" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.energy).must_equal runner.max_energy
    end

    it "starts with zero shield" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.shield_level).must_equal 0
    end

    it "starts at origin" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.x).must_equal 0.0
      _(runner.y).must_equal 0.0
    end

    it "starts with zero velocity" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.velocity_x).must_equal 0.0
      _(runner.velocity_y).must_equal 0.0
    end

    it "creates an instance of the rubot class" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.instance).must_be_instance_of DummyBot
    end

    it "uses size from rubot class" do
      runner = Rubowar::RubotActor.new(SmallDummyBot)

      _(runner.size).must_equal :small
    end
  end

  describe "#radius" do
    it "returns 16 for small rubots" do
      runner = Rubowar::RubotActor.new(SmallDummyBot)

      _(runner.radius).must_equal 16
    end

    it "returns 20 for medium rubots" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.radius).must_equal 20
    end

    it "returns 24 for large rubots" do
      runner = Rubowar::RubotActor.new(LargeDummyBot)

      _(runner.radius).must_equal 24
    end
  end

  describe "#energy_regen" do
    it "returns 8 for small rubots" do
      runner = Rubowar::RubotActor.new(SmallDummyBot)

      _(runner.energy_regen).must_equal 8
    end

    it "returns 10 for medium rubots" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.energy_regen).must_equal 10
    end

    it "returns 12 for large rubots" do
      runner = Rubowar::RubotActor.new(LargeDummyBot)

      _(runner.energy_regen).must_equal 12
    end
  end

  describe "#max_health" do
    it "returns 80 for small rubots" do
      runner = Rubowar::RubotActor.new(SmallDummyBot)

      _(runner.max_health).must_equal 80
    end

    it "returns 100 for medium rubots" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.max_health).must_equal 100
    end

    it "returns 120 for large rubots" do
      runner = Rubowar::RubotActor.new(LargeDummyBot)

      _(runner.max_health).must_equal 120
    end
  end

  describe "#max_shield" do
    it "equals max_health for small rubots" do
      runner = Rubowar::RubotActor.new(SmallDummyBot)

      _(runner.max_shield).must_equal 80
    end

    it "equals max_health for medium rubots" do
      runner = Rubowar::RubotActor.new(DummyBot)

      _(runner.max_shield).must_equal 100
    end

    it "equals max_health for large rubots" do
      runner = Rubowar::RubotActor.new(LargeDummyBot)

      _(runner.max_shield).must_equal 120
    end
  end

  describe "#speed" do
    it "calculates speed from velocity" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.velocity_x = 3.0
      runner.velocity_y = 4.0

      _(runner.speed).must_equal 5.0
    end
  end

  describe "#alive? and #dead?" do
    it "is alive when health is positive" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.health = 1

      _(runner.alive?).must_equal true
      _(runner.dead?).must_equal false
    end

    it "is dead when health is zero" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.health = 0

      _(runner.alive?).must_equal false
      _(runner.dead?).must_equal true
    end
  end

  describe "#apply_damage" do
    it "reduces health by damage amount" do
      runner = Rubowar::RubotActor.new(DummyBot)

      runner.apply_damage(30)

      _(runner.health).must_equal 70
    end

    it "tracks damage taken" do
      runner = Rubowar::RubotActor.new(DummyBot)

      runner.apply_damage(30)

      _(runner.damage_taken).must_equal 30
    end

    it "absorbs damage with shield first" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.shield_level = 20

      runner.apply_damage(30)

      _(runner.shield_level).must_equal 0
      _(runner.health).must_equal 90
    end

    it "does not reduce health below zero" do
      runner = Rubowar::RubotActor.new(DummyBot)

      runner.apply_damage(150)

      _(runner.health).must_equal 0
    end
  end

  describe "#spend_energy" do
    it "returns true and reduces energy when sufficient" do
      runner = Rubowar::RubotActor.new(DummyBot)

      result = runner.spend_energy(30)

      _(result).must_equal true
      _(runner.energy).must_equal 70
    end

    it "returns false and drains to zero when insufficient" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.energy = 20

      result = runner.spend_energy(50)

      _(result).must_equal false
      _(runner.energy).must_equal 0
    end
  end

  describe "#regenerate_energy" do
    it "adds energy regen amount" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.energy = 50

      runner.regenerate_energy

      _(runner.energy).must_equal 60
    end

    it "caps energy at max" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.energy = runner.max_energy - 5

      runner.regenerate_energy

      _(runner.energy).must_equal runner.max_energy
    end
  end

  describe "#degrade_shield" do
    it "reduces shield by 12% (proportional decay)" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.shield_level = 100

      runner.degrade_shield

      _(runner.shield_level).must_equal 88 # 100 * 0.88 = 88
    end

    it "floors the result" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.shield_level = 20

      runner.degrade_shield

      _(runner.shield_level).must_equal 17 # 20 * 0.88 = 17.6 → 17
    end

    it "decays to zero from low values" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.shield_level = 1

      runner.degrade_shield

      _(runner.shield_level).must_equal 0 # 1 * 0.88 = 0.88 → 0
    end
  end

  describe "#clamp_speed" do
    it "does nothing when under max speed" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.velocity_x = 10.0
      runner.velocity_y = 10.0

      runner.clamp_speed

      _(runner.velocity_x).must_equal 10.0
      _(runner.velocity_y).must_equal 10.0
    end

    it "scales velocity to max speed when over" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.velocity_x = 600.0
      runner.velocity_y = 800.0 # speed = 1000, over cap

      runner.clamp_speed

      _(runner.speed).must_be_close_to Rubowar::Config::Physics::MAX_SPEED, 0.001
    end
  end

  describe "#to_state" do
    it "returns a RubotState with current values" do
      runner = Rubowar::RubotActor.new(DummyBot)
      runner.x = 100.0
      runner.y = 200.0
      runner.health = 80

      state = runner.to_state

      _(state).must_be_instance_of Rubowar::RubotState
      _(state.x).must_equal 100.0
      _(state.y).must_equal 200.0
      _(state.health).must_equal 80
    end
  end
end
