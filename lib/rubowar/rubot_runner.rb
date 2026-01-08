# frozen_string_literal: true

# [file]
# purpose = "Internal mutable state tracker for the game engine"
# responsibility = "Track position, health, energy, and stats for each rubot"
# pattern = "State Container"
#
# [class.RubotRunner]
# purpose = "Wraps a Rubot instance with mutable game state"
# note = "Players never interact with this directly - they get immutable RubotState snapshots"
# collaborators = ["Arena", "Battle", "RubotState"]
#
# [sizes]
# small = { radius: 16, energy_regen: 8, max_health: 80, max_energy: 120 }
# medium = { radius: 20, energy_regen: 10, max_health: 100, max_energy: 100 }
# large = { radius: 24, energy_regen: 12, max_health: 120, max_energy: 80 }
# tradeoffs = "Small = agile, high energy cap. Large = tanky, high regen, low energy cap"
#
# [damage_methods]
# apply_damage = "Normal damage, shields absorb first"
# apply_collision_damage = "Physical impact, bypasses shields"

module Rubowar
  class RubotRunner
    attr_accessor :x, :y, :velocity_x, :velocity_y, :turret_angle, :health, :energy, :shield_level, :damage_dealt,
                  :damage_taken, :times_probed, :times_scanned, :times_pulsed
    attr_reader :size, :rubot_class, :instance

    def initialize(rubot_class)
      @rubot_class = rubot_class
      @size = rubot_class.size
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
      @times_probed = 0
      @times_scanned = 0
      @times_pulsed = 0
      @instance = rubot_class.new
    end

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
      Config::Rubot::SIZES[@size][:max_energy]
    end

    def max_shield
      max_health # Shield cap equals HP cap
    end

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

    # Apply collision damage (bypasses shields - physical impact)
    def apply_collision_damage(amount)
      @health -= amount
      @health = 0 if @health.negative?
      @damage_taken += amount
    end

    def regenerate_energy
      @energy = [@energy + energy_regen, max_energy].min
    end

    def degrade_shield
      @shield_level = (@shield_level * (1 - Config::Rubot::SHIELD_DECAY_RATE)).floor
    end

    def reset_detection_counts
      @times_probed = 0
      @times_scanned = 0
      @times_pulsed = 0
    end

    # Attempts to spend energy. If insufficient energy, drains to zero and returns false.
    # This penalizes rubots for attempting actions they can't afford.
    def spend_energy(amount)
      if amount > @energy
        @energy = 0
        false
      else
        @energy -= amount
        true
      end
    end

    def clamp_speed
      current_speed = speed
      return unless current_speed > Config::Physics::MAX_SPEED

      scale = Config::Physics::MAX_SPEED / current_speed
      @velocity_x *= scale
      @velocity_y *= scale
    end

    # Safely call a method on the rubot instance, penalizing errors with damage
    # @param method [Symbol] method name to call
    # @param args [Array] arguments to pass
    # @return [Object, nil] return value or nil on error
    def safe_callback(method, *)
      return nil if dead?

      @instance.public_send(method, *)
    rescue StandardError => e
      apply_collision_damage(Config::Battle::ERROR_DAMAGE)
      warn "[#{@rubot_class.name}] Error in #{method}: #{e.class} - #{e.message}"
      nil
    end
  end
end
