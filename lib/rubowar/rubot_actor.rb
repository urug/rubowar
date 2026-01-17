# frozen_string_literal: true

require "securerandom"

# [file]
# purpose = "State container and resource management for rubot actors"
# responsibility = "Track health, energy, shields, damage stats, and detection counts"
# pattern = "Mixin Module"
#
# [module.RubotActor]
# purpose = "Provides state accessors and resource management for actors"
# note = "Include alongside RubotPhysics in LocalActor, BasicActor, etc."
# collaborators = ["RubotPhysics", "Arena", "Battle", "RubotState"]
#
# [sizes]
# small = { radius: 16, energy_regen: 8, max_health: 80 }
# medium = { radius: 20, energy_regen: 10, max_health: 100 }
# large = { radius: 24, energy_regen: 12, max_health: 120 }
# tradeoffs = "Small = agile, cheap thrust. Large = tanky, high regen, harder to hit"
#
# [implementor_requirements]
# required_methods = [
#   "instance - returns the rubot instance (or self for stubs)",
#   "act - called each chronon to collect actions",
#   "rubot_actions - returns { sense: [], move: [], combat: [] }",
#   "reset_actions - resets actions hash for new chronon",
#   "set_sensing_results(probe:, scan:, pulse:, detect:) - stores sensing results",
#   "call_safely { |instance| } - safe callback execution with error handling",
#   "call_on_death - death callback"
# ]

module Rubowar
  module RubotActor
    attr_accessor :x, :y, :velocity_x, :velocity_y, :health, :energy, :shield_level, :damage_dealt,
                  :damage_taken, :death_processed, :_act_completed
    attr_reader :id, :size, :detection_counts, :position_set, :turret_angle

    # Initialize shared actor state. Call this from the including class's initialize method.
    # @param size [Symbol] The rubot size (:small, :medium, :large)
    def initialize_actor(size:)
      @id = "#{Config::Ids::RUBOT_PREFIX}-#{SecureRandom.hex(4)}"
      @size = size
      @x = 0.0
      @y = 0.0
      @velocity_x = 0.0
      @velocity_y = 0.0
      @turret_angle = 0.0
      @health = max_health
      @energy = max_energy
      @shield_level = 0
      @damage_dealt = 0
      @damage_taken = 0
      @detection_counts = { probed: 0, scanned: 0, pulsed: 0 }
      @position_set = false
      @death_processed = false
      @_act_completed = false
    end

    # === Size-based configuration ===

    def radius
      Config::Rubot::SIZES[@size][:radius]
    end

    def energy_regen
      Config::Rubot::SIZES[@size][:energy_regen]
    end

    def max_health
      Config::Rubot::SIZES[@size][:max_health]
    end

    def max_energy
      Config::Rubot::MAX_ENERGY
    end

    def max_shield
      max_health # Shield cap equals HP cap
    end

    # === State queries ===

    def speed
      Math.sqrt((@velocity_x**2) + (@velocity_y**2))
    end

    def alive?
      @health.positive?
    end

    def dead?
      !alive?
    end

    def to_state
      RubotState.new(
        x: @x,
        y: @y,
        velocity_x: @velocity_x,
        velocity_y: @velocity_y,
        speed:,
        turret_angle: @turret_angle,
        health: @health,
        energy: @energy,
        shield_level: @shield_level,
        damage_dealt: @damage_dealt,
        damage_taken: @damage_taken,
        size: @size
      )
    end

    # === Damage handling ===

    # Normal damage - shields absorb first
    def apply_damage(amount)
      if @shield_level.positive?
        absorbed = [@shield_level, amount].min
        @shield_level -= absorbed
        amount -= absorbed
      end

      @health -= amount
      @health = 0 if @health.negative?
      @damage_taken += amount
    end

    # Collision damage - bypasses shields (physical impact)
    def apply_collision_damage(amount)
      @health -= amount
      @health = 0 if @health.negative?
      @damage_taken += amount
    end

    # === Energy management ===

    def regenerate_energy
      @energy = [@energy + energy_regen, max_energy].min
    end

    # Attempts to spend energy. If insufficient energy, drains to zero and returns false.
    # This penalizes rubots for attempting actions they can't afford.
    def spend_energy(amount)
      NumericValidation.validate!(amount, name: "energy amount", non_negative: true)

      if amount > @energy
        @energy = 0
        false
      else
        @energy -= amount
        true
      end
    end

    def add_energy(amount)
      @energy = [@energy + amount, max_energy].min
    end

    # === Shield management ===

    def degrade_shield
      @shield_level = (@shield_level * (1 - Config::Rubot::SHIELD_DECAY_RATE)).floor
    end

    def add_shield(amount)
      @shield_level = [@shield_level + amount, max_shield].min
    end

    def increase_shielding(energy)
      NumericValidation.validate!(energy, name: "shield energy", positive: true)

      return false unless spend_energy(energy)

      add_shield(energy)
      true
    end

    # === Combat stats ===

    def add_damage_dealt(amount)
      @damage_dealt += amount
    end

    # === Detection ===

    def reset_detection_counts
      @detection_counts = { probed: 0, scanned: 0, pulsed: 0 }
    end

    def increment_detection(type)
      @detection_counts[type] += 1
    end

    def process_detect
      return false unless spend_energy(SensorCalculator.detect_cost)

      set_sensing_results(detect: @detection_counts.dup.freeze)
      true
    end

    private

    def validate_size!(size, context = nil)
      return if Config::Rubot::SIZES.key?(size)

      valid_sizes = Config::Rubot::SIZES.keys.join(", ")
      context_msg =
        if context
          " for #{context.respond_to?(:name) ? context.name : context}"
        else
          ""
        end
      raise InvalidRubotSizeError, "Invalid rubot size '#{size}'#{context_msg}. Must be one of: #{valid_sizes}"
    end
  end
end
