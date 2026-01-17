# frozen_string_literal: true

require "test_helper"

class DummyResourceBot
  include Rubowar::Rubot

  size :medium
  def act; end
end

class SmallResourceBot
  include Rubowar::Rubot

  size :small
  def act; end
end

class LargeResourceBot
  include Rubowar::Rubot

  size :large
  def act; end
end

describe Rubowar::RubotResources do
  describe "#max_energy" do
    it "returns the configured max energy" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      _(actor.max_energy).must_equal Rubowar::Config::Rubot::MAX_ENERGY
    end
  end

  describe "#max_shield" do
    it "equals max_health for small rubots" do
      actor = Rubowar::LocalActor.new(SmallResourceBot)

      _(actor.max_shield).must_equal Rubowar::Config::Rubot::SIZES[:small][:max_health]
    end

    it "equals max_health for medium rubots" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      _(actor.max_shield).must_equal Rubowar::Config::Rubot::SIZES[:medium][:max_health]
    end

    it "equals max_health for large rubots" do
      actor = Rubowar::LocalActor.new(LargeResourceBot)

      _(actor.max_shield).must_equal Rubowar::Config::Rubot::SIZES[:large][:max_health]
    end
  end

  describe "#apply_damage" do
    it "reduces health by damage amount" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      actor.apply_damage(30)

      _(actor.health).must_equal actor.max_health - 30
    end

    it "tracks damage taken" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      actor.apply_damage(30)

      _(actor.damage_taken).must_equal 30
    end

    it "absorbs damage with shield first" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.shield_level = 20

      actor.apply_damage(30)

      _(actor.shield_level).must_equal 0
      _(actor.health).must_equal actor.max_health - 10
    end

    it "partially absorbs damage when shield is less than damage" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.shield_level = 10

      actor.apply_damage(30)

      _(actor.shield_level).must_equal 0
      _(actor.health).must_equal actor.max_health - 20
      _(actor.damage_taken).must_equal 20
    end

    it "does not reduce health below zero" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      actor.apply_damage(150)

      _(actor.health).must_equal 0
    end
  end

  describe "#apply_collision_damage" do
    it "reduces health directly bypassing shields" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.shield_level = 50

      actor.apply_collision_damage(20)

      _(actor.health).must_equal actor.max_health - 20
      _(actor.shield_level).must_equal 50
    end

    it "tracks damage taken" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      actor.apply_collision_damage(15)

      _(actor.damage_taken).must_equal 15
    end

    it "does not reduce health below zero" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      actor.apply_collision_damage(150)

      _(actor.health).must_equal 0
    end
  end

  describe "#regenerate_energy" do
    it "adds energy regen amount" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.energy = 50

      actor.regenerate_energy

      _(actor.energy).must_equal 50 + actor.energy_regen
    end

    it "caps energy at max" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.energy = actor.max_energy - 5

      actor.regenerate_energy

      _(actor.energy).must_equal actor.max_energy
    end
  end

  describe "#spend_energy" do
    it "returns true and reduces energy when sufficient" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      result = actor.spend_energy(30)

      _(result).must_equal true
      _(actor.energy).must_equal 70
    end

    it "returns false and drains to zero when insufficient" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.energy = 20

      result = actor.spend_energy(50)

      _(result).must_equal false
      _(actor.energy).must_equal 0
    end

    it "raises error for negative amount" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      _(-> { actor.spend_energy(-10) }).must_raise Rubowar::InvalidActionError
    end
  end

  describe "#add_energy" do
    it "increases energy by amount" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.energy = 50

      actor.add_energy(20)

      _(actor.energy).must_equal 70
    end

    it "caps energy at max" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.energy = 90

      actor.add_energy(50)

      _(actor.energy).must_equal actor.max_energy
    end
  end

  describe "#degrade_shield" do
    it "reduces shield by decay rate" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.shield_level = 100

      actor.degrade_shield

      _(actor.shield_level).must_equal 88
    end

    it "floors the result" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.shield_level = 20

      actor.degrade_shield

      _(actor.shield_level).must_equal 17
    end

    it "decays to zero from low values" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.shield_level = 1

      actor.degrade_shield

      _(actor.shield_level).must_equal 0
    end
  end

  describe "#add_shield" do
    it "increases shield level" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.shield_level = 20

      actor.add_shield(15)

      _(actor.shield_level).must_equal 35
    end

    it "caps shield at max_shield" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.shield_level = 90

      actor.add_shield(50)

      _(actor.shield_level).must_equal actor.max_shield
    end
  end

  describe "#increase_shielding" do
    it "adds shield equal to energy spent" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.shield_level = 10

      actor.increase_shielding(20)

      _(actor.shield_level).must_equal 30
    end

    it "spends the specified energy" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.energy = 50

      actor.increase_shielding(20)

      _(actor.energy).must_equal 30
    end

    it "returns false when insufficient energy" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)
      actor.energy = 10

      result = actor.increase_shielding(20)

      _(result).must_equal false
    end

    it "returns true when successful" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      result = actor.increase_shielding(20)

      _(result).must_equal true
    end

    it "raises error for non-positive energy" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      _(-> { actor.increase_shielding(0) }).must_raise Rubowar::InvalidActionError
    end
  end

  describe "#add_damage_dealt" do
    it "increases damage dealt counter" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      actor.add_damage_dealt(25)

      _(actor.damage_dealt).must_equal 25
    end

    it "accumulates across multiple calls" do
      actor = Rubowar::LocalActor.new(DummyResourceBot)

      actor.add_damage_dealt(10)
      actor.add_damage_dealt(15)

      _(actor.damage_dealt).must_equal 25
    end
  end
end
