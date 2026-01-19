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
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.health).must_equal actor.max_health
    end

    it "starts with full energy" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.energy).must_equal actor.max_energy
    end

    it "starts with zero shield" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.shield_level).must_equal 0
    end

    it "starts at origin" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.x).must_equal 0.0
      _(actor.y).must_equal 0.0
    end

    it "starts with zero velocity" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.velocity_x).must_equal 0.0
      _(actor.velocity_y).must_equal 0.0
    end

    it "creates an instance of the rubot class" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.instance).must_be_instance_of DummyBot
    end

    it "uses size from rubot class" do
      actor = Rubowar::LocalActor.new(SmallDummyBot)

      _(actor.size).must_equal :small
    end

    it "defaults name to rubot class name" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.name).must_equal "DummyBot"
    end

    it "uses custom name when provided" do
      actor = Rubowar::LocalActor.new(DummyBot, name: "The Destroyer")

      _(actor.name).must_equal "The Destroyer"
    end
  end

  describe "BasicActor" do
    it "defaults name to BasicActor" do
      actor = Rubowar::BasicActor.new

      _(actor.name).must_equal "BasicActor"
    end

    it "uses custom name when provided" do
      actor = Rubowar::BasicActor.new(name: "Test Fighter")

      _(actor.name).must_equal "Test Fighter"
    end
  end

  describe "#radius" do
    it "returns configured radius for small rubots" do
      actor = Rubowar::LocalActor.new(SmallDummyBot)

      _(actor.radius).must_equal Rubowar::Config::Rubot::SIZES[:small][:radius]
    end

    it "returns configured radius for medium rubots" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.radius).must_equal Rubowar::Config::Rubot::SIZES[:medium][:radius]
    end

    it "returns configured radius for large rubots" do
      actor = Rubowar::LocalActor.new(LargeDummyBot)

      _(actor.radius).must_equal Rubowar::Config::Rubot::SIZES[:large][:radius]
    end
  end

  describe "#energy_regen" do
    it "returns configured value for small rubots" do
      actor = Rubowar::LocalActor.new(SmallDummyBot)

      _(actor.energy_regen).must_equal Rubowar::Config::Rubot::SIZES[:small][:energy_regen]
    end

    it "returns configured value for medium rubots" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.energy_regen).must_equal Rubowar::Config::Rubot::SIZES[:medium][:energy_regen]
    end

    it "returns configured value for large rubots" do
      actor = Rubowar::LocalActor.new(LargeDummyBot)

      _(actor.energy_regen).must_equal Rubowar::Config::Rubot::SIZES[:large][:energy_regen]
    end
  end

  describe "#max_health" do
    it "returns configured value for small rubots" do
      actor = Rubowar::LocalActor.new(SmallDummyBot)

      _(actor.max_health).must_equal Rubowar::Config::Rubot::SIZES[:small][:max_health]
    end

    it "returns configured value for medium rubots" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.max_health).must_equal Rubowar::Config::Rubot::SIZES[:medium][:max_health]
    end

    it "returns configured value for large rubots" do
      actor = Rubowar::LocalActor.new(LargeDummyBot)

      _(actor.max_health).must_equal Rubowar::Config::Rubot::SIZES[:large][:max_health]
    end
  end

  describe "#max_shield" do
    it "equals max_health for small rubots" do
      actor = Rubowar::LocalActor.new(SmallDummyBot)

      _(actor.max_shield).must_equal Rubowar::Config::Rubot::SIZES[:small][:max_health]
    end

    it "equals max_health for medium rubots" do
      actor = Rubowar::LocalActor.new(DummyBot)

      _(actor.max_shield).must_equal Rubowar::Config::Rubot::SIZES[:medium][:max_health]
    end

    it "equals max_health for large rubots" do
      actor = Rubowar::LocalActor.new(LargeDummyBot)

      _(actor.max_shield).must_equal Rubowar::Config::Rubot::SIZES[:large][:max_health]
    end
  end

  describe "#speed" do
    it "calculates speed from velocity" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.velocity_x = 3.0
      actor.velocity_y = 4.0

      _(actor.speed).must_equal 5.0
    end
  end

  describe "#alive? and #dead?" do
    it "is alive when health is positive" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.health = 1

      _(actor.alive?).must_equal true
      _(actor.dead?).must_equal false
    end

    it "is dead when health is zero" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.health = 0

      _(actor.alive?).must_equal false
      _(actor.dead?).must_equal true
    end
  end

  describe "#apply_damage" do
    it "reduces health by damage amount" do
      actor = Rubowar::LocalActor.new(DummyBot)

      actor.apply_damage(30)

      _(actor.health).must_equal actor.max_health - 30
    end

    it "tracks damage taken" do
      actor = Rubowar::LocalActor.new(DummyBot)

      actor.apply_damage(30)

      _(actor.damage_taken).must_equal 30
    end

    it "absorbs damage with shield first" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.shield_level = 20

      actor.apply_damage(30)

      _(actor.shield_level).must_equal 0
      _(actor.health).must_equal actor.max_health - 10
    end

    it "does not reduce health below zero" do
      actor = Rubowar::LocalActor.new(DummyBot)

      actor.apply_damage(150)

      _(actor.health).must_equal 0
    end
  end

  describe "#spend_energy" do
    it "returns true and reduces energy when sufficient" do
      actor = Rubowar::LocalActor.new(DummyBot)

      result = actor.spend_energy(30)

      _(result).must_equal true
      _(actor.energy).must_equal 70
    end

    it "returns false and drains to zero when insufficient" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 20

      result = actor.spend_energy(50)

      _(result).must_equal false
      _(actor.energy).must_equal 0
    end
  end

  describe "#regenerate_energy" do
    it "adds energy regen amount" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 50

      actor.regenerate_energy

      _(actor.energy).must_equal 50 + actor.energy_regen
    end

    it "caps energy at max" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = actor.max_energy - 5

      actor.regenerate_energy

      _(actor.energy).must_equal actor.max_energy
    end
  end

  describe "#degrade_shield" do
    it "reduces shield by 12% (proportional decay)" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.shield_level = 100

      actor.degrade_shield

      _(actor.shield_level).must_equal 88 # 100 * 0.88 = 88
    end

    it "floors the result" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.shield_level = 20

      actor.degrade_shield

      _(actor.shield_level).must_equal 17 # 20 * 0.88 = 17.6 → 17
    end

    it "decays to zero from low values" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.shield_level = 1

      actor.degrade_shield

      _(actor.shield_level).must_equal 0 # 1 * 0.88 = 0.88 → 0
    end
  end

  describe "#to_state" do
    it "returns a RubotState with current values" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.x = 100.0
      actor.y = 200.0
      actor.health = 80

      state = actor.to_state

      _(state).must_be_instance_of Rubowar::RubotState
      _(state.x).must_equal 100.0
      _(state.y).must_equal 200.0
      _(state.health).must_equal 80
    end
  end

  describe "#apply_collision_damage" do
    it "reduces health directly bypassing shields" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.shield_level = 50

      actor.apply_collision_damage(20)

      _(actor.health).must_equal actor.max_health - 20
      _(actor.shield_level).must_equal 50
    end

    it "tracks damage taken" do
      actor = Rubowar::LocalActor.new(DummyBot)

      actor.apply_collision_damage(15)

      _(actor.damage_taken).must_equal 15
    end

    it "does not reduce health below zero" do
      actor = Rubowar::LocalActor.new(DummyBot)

      actor.apply_collision_damage(150)

      _(actor.health).must_equal 0
    end
  end

  describe "#apply_friction" do
    it "multiplies velocity by friction factor" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.velocity_x = 10.0
      actor.velocity_y = 10.0

      actor.apply_friction(0.9)

      _(actor.velocity_x).must_equal 9.0
      _(actor.velocity_y).must_equal 9.0
    end
  end

  describe "#move" do
    it "adds velocity to position" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.x = 100.0
      actor.y = 200.0
      actor.velocity_x = 5.0
      actor.velocity_y = -3.0

      actor.move

      _(actor.x).must_equal 105.0
      _(actor.y).must_equal 197.0
    end
  end

  describe "#set_position" do
    it "sets x and y coordinates" do
      actor = Rubowar::LocalActor.new(DummyBot)

      actor.set_position(x: 150.0, y: 250.0)

      _(actor.x).must_equal 150.0
      _(actor.y).must_equal 250.0
    end
  end

  describe "#set_velocity" do
    it "sets velocity components" do
      actor = Rubowar::LocalActor.new(DummyBot)

      actor.set_velocity(vx: 8.0, vy: -4.0)

      _(actor.velocity_x).must_equal 8.0
      _(actor.velocity_y).must_equal(-4.0)
    end
  end

  describe "#adjust_velocity" do
    it "adds to existing velocity" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.velocity_x = 5.0
      actor.velocity_y = 3.0

      actor.adjust_velocity(dvx: 2.0, dvy: -1.0)

      _(actor.velocity_x).must_equal 7.0
      _(actor.velocity_y).must_equal 2.0
    end
  end

  describe "#adjust_position" do
    it "adds to existing position" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.x = 100.0
      actor.y = 200.0

      actor.adjust_position(dx: 10.0, dy: -5.0)

      _(actor.x).must_equal 110.0
      _(actor.y).must_equal 195.0
    end
  end

  describe "#add_shield" do
    it "increases shield level" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.shield_level = 20

      actor.add_shield(15)

      _(actor.shield_level).must_equal 35
    end

    it "caps shield at max_shield" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.shield_level = 90

      actor.add_shield(50)

      _(actor.shield_level).must_equal actor.max_shield
    end
  end

  describe "#turn_turret" do
    it "rotates turret by degrees" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.turret_angle = 45.0

      actor.turn_turret(30)

      _(actor.turret_angle).must_equal 75.0
    end

    it "wraps angle at 360" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.turret_angle = 350.0

      actor.turn_turret(20)

      _(actor.turret_angle).must_equal 10.0
    end

    it "spends energy based on degrees" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 50

      actor.turn_turret(24) # Cost: ceil(24/24) = 1

      _(actor.energy).must_equal 49
    end

    it "returns false when insufficient energy" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 0

      result = actor.turn_turret(24)

      _(result).must_equal false
    end

    it "returns true when successful" do
      actor = Rubowar::LocalActor.new(DummyBot)

      result = actor.turn_turret(24)

      _(result).must_equal true
    end
  end

  describe "#increase_shielding" do
    it "adds shield equal to energy spent" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.shield_level = 10

      actor.increase_shielding(20)

      _(actor.shield_level).must_equal 30
    end

    it "spends the specified energy" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 50

      actor.increase_shielding(20)

      _(actor.energy).must_equal 30
    end

    it "returns false when insufficient energy" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 10

      result = actor.increase_shielding(20)

      _(result).must_equal false
    end

    it "returns true when successful" do
      actor = Rubowar::LocalActor.new(DummyBot)

      result = actor.increase_shielding(20)

      _(result).must_equal true
    end
  end

  describe "#thrust" do
    it "adds velocity in specified direction" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 100

      actor.thrust(speed: 3, angle: 0)

      _(actor.velocity_x).must_be :>, 0
      _(actor.velocity_y).must_be_close_to 0, 0.01
    end

    it "spends energy based on speed and mass" do
      actor = Rubowar::LocalActor.new(DummyBot)
      initial_energy = actor.energy

      actor.thrust(speed: 3, angle: 0)

      _(actor.energy).must_be :<, initial_energy
    end

    it "returns false when no energy" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 0

      result = actor.thrust(speed: 3, angle: 0)

      _(result).must_equal false
    end

    it "returns true when successful" do
      actor = Rubowar::LocalActor.new(DummyBot)

      result = actor.thrust(speed: 3, angle: 0)

      _(result).must_equal true
    end

    it "provides partial thrust when energy insufficient for full speed" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 1

      actor.thrust(speed: 10, angle: 0)

      _(actor.energy).must_equal 0
      _(actor.velocity_x).must_be :>, 0
      _(actor.velocity_x).must_be :<, 10
    end
  end

  describe "#process_detect" do
    it "sets detect_intel on instance" do
      actor = Rubowar::LocalActor.new(DummyBot)
      2.times { actor.increment_detection(:probed) }
      3.times { actor.increment_detection(:scanned) }
      actor.increment_detection(:pulsed)

      actor.process_detect

      result = actor.instance.detect_intel
      _(result[:probed]).must_equal 2
      _(result[:scanned]).must_equal 3
      _(result[:pulsed]).must_equal 1
    end

    it "spends energy" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 50

      actor.process_detect

      _(actor.energy).must_equal 50 - Rubowar::Config::Sensing::DETECT_COST
    end

    it "returns false when insufficient energy" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.energy = 0

      result = actor.process_detect

      _(result).must_equal false
    end

    it "returns true when successful" do
      actor = Rubowar::LocalActor.new(DummyBot)

      result = actor.process_detect

      _(result).must_equal true
    end
  end

  describe "#reset_detection_counts" do
    it "resets all detection counters to zero" do
      actor = Rubowar::LocalActor.new(DummyBot)
      5.times { actor.increment_detection(:probed) }
      3.times { actor.increment_detection(:scanned) }
      2.times { actor.increment_detection(:pulsed) }

      actor.reset_detection_counts

      _(actor.detection_counts[:probed]).must_equal 0
      _(actor.detection_counts[:scanned]).must_equal 0
      _(actor.detection_counts[:pulsed]).must_equal 0
    end
  end

  describe "#increment_detection" do
    it "increments the probed count" do
      actor = Rubowar::LocalActor.new(DummyBot)

      actor.increment_detection(:probed)
      actor.increment_detection(:probed)

      _(actor.detection_counts[:probed]).must_equal 2
    end

    it "increments the scanned count" do
      actor = Rubowar::LocalActor.new(DummyBot)

      actor.increment_detection(:scanned)

      _(actor.detection_counts[:scanned]).must_equal 1
    end

    it "increments the pulsed count" do
      actor = Rubowar::LocalActor.new(DummyBot)

      3.times { actor.increment_detection(:pulsed) }

      _(actor.detection_counts[:pulsed]).must_equal 3
    end
  end

  describe "#call_safely" do
    it "calls block with instance" do
      actor = Rubowar::LocalActor.new(DummyBot)

      # act is defined on DummyBot
      result = actor.call_safely(&:act)

      _(result).must_be_nil # act returns nil
    end

    it "returns nil when actor is dead" do
      actor = Rubowar::LocalActor.new(DummyBot)
      actor.health = 0

      result = actor.call_safely(&:act)

      _(result).must_be_nil
    end

    it "applies damage when callback raises error" do
      error_bot_class = Class.new do
        include Rubowar::Rubot

        def act
          raise "Test error"
        end
      end
      actor = Rubowar::LocalActor.new(error_bot_class)
      initial_health = actor.health

      actor.call_safely(&:act)

      _(actor.health).must_equal initial_health - Rubowar::Config::Battle::ERROR_DAMAGE
    end

    it "returns nil when callback raises error" do
      error_bot_class = Class.new do
        include Rubowar::Rubot

        def act
          raise "Test error"
        end
      end
      actor = Rubowar::LocalActor.new(error_bot_class)

      result = actor.call_safely(&:act)

      _(result).must_be_nil
    end

    it "passes arguments via block" do
      callback_bot_class = Class.new do
        include Rubowar::Rubot

        attr_reader :received_damage, :received_direction

        def on_hit(damage:, direction:)
          @received_damage = damage
          @received_direction = direction
        end
      end
      actor = Rubowar::LocalActor.new(callback_bot_class)

      actor.call_safely { |bot| bot.on_hit(damage: 15, direction: 90) }

      _(actor.instance.received_damage).must_equal 15
      _(actor.instance.received_direction).must_equal 90
    end
  end
end
