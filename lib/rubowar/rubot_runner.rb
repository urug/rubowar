# frozen_string_literal: true

module Rubowar
  class RubotRunner
    SIZES = {
      small: { radius: 15, energy_regen: 8, max_health: 80 },
      medium: { radius: 20, energy_regen: 10, max_health: 100 },
      large: { radius: 25, energy_regen: 12, max_health: 120 }
    }.freeze
    MAX_ENERGY = 100
    MAX_SPEED = 20
    SHIELD_DECAY_RATE = 0.12

    attr_accessor :x, :y, :velocity_x, :velocity_y
    attr_accessor :turret_angle
    attr_accessor :health, :energy, :shield_level
    attr_accessor :damage_dealt, :damage_taken
    attr_accessor :times_probed, :times_scanned, :times_pulsed
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
      @energy = MAX_ENERGY
      @shield_level = 0
      @damage_dealt = 0
      @damage_taken = 0
      @times_probed = 0
      @times_scanned = 0
      @times_pulsed = 0
      @instance = rubot_class.new
    end

    def radius
      SIZES[@size][:radius]
    end

    def energy_regen
      SIZES[@size][:energy_regen]
    end

    def max_health
      SIZES[@size][:max_health]
    end

    def max_shield
      max_health # Shield cap equals HP cap
    end

    def speed
      Math.sqrt(@velocity_x**2 + @velocity_y**2)
    end

    def alive?
      @health > 0
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
        speed: speed,
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
      if @shield_level > 0
        absorbed = [@shield_level, amount].min
        @shield_level -= absorbed
        amount -= absorbed
      end

      @health -= amount
      @health = 0 if @health < 0
      @damage_taken += amount
    end

    def regenerate_energy
      @energy = [@energy + energy_regen, MAX_ENERGY].min
    end

    def degrade_shield
      @shield_level = (@shield_level * (1 - SHIELD_DECAY_RATE)).floor
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
      return unless current_speed > MAX_SPEED

      scale = MAX_SPEED / current_speed
      @velocity_x *= scale
      @velocity_y *= scale
    end
  end
end
