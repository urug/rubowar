# frozen_string_literal: true

# [file]
# purpose = "Internal mutable state tracker for the game engine"
# responsibility = "Track position, health, energy, and stats for each rubot"
# pattern = "State Container"
#
# [class.RubotActor]
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
  class RubotActor
    attr_accessor :x, :y, :velocity_x, :velocity_y, :turret_angle, :health, :energy, :shield_level, :damage_dealt,
                  :damage_taken
    attr_reader :size, :rubot_class, :instance, :detection_counts

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
      @detection_counts = { probed: 0, scanned: 0, pulsed: 0 }
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
      @detection_counts = { probed: 0, scanned: 0, pulsed: 0 }
    end

    def increment_detection(type)
      @detection_counts[type] += 1
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

    def apply_friction(friction)
      @velocity_x *= friction
      @velocity_y *= friction
    end

    def move
      @x += @velocity_x
      @y += @velocity_y
    end

    def set_position(x, y)
      @x = x
      @y = y
    end

    def set_velocity(vx, vy)
      @velocity_x = vx
      @velocity_y = vy
    end

    def set_turret_angle(angle)
      @turret_angle = angle % 360
    end

    def clamp_x(min, max)
      @x = min if @x < min
      @x = max if @x > max
    end

    def clamp_y(min, max)
      @y = min if @y < min
      @y = max if @y > max
    end

    def add_damage_dealt(amount)
      @damage_dealt += amount
    end

    def add_energy(amount)
      @energy = [@energy + amount, max_energy].min
    end

    def adjust_velocity(dvx, dvy)
      @velocity_x += dvx
      @velocity_y += dvy
    end

    def adjust_position(dx, dy)
      @x += dx
      @y += dy
    end

    def add_shield(amount)
      @shield_level = [@shield_level + amount, max_shield].min
    end

    def process_detect
      return false unless spend_energy(SensorCalculations.detect_cost)

      @instance.detect_result = @detection_counts.dup
      true
    end

    def turn_turret(degrees)
      cost = (degrees.abs / Config::Combat::TURRET_TURN_DIVISOR).ceil
      return false unless spend_energy(cost)

      @turret_angle = (@turret_angle + degrees) % 360
      true
    end

    def increase_shielding(energy)
      return false unless spend_energy(energy)

      add_shield(energy)
      true
    end

    def thrust(speed:, angle:)
      return false if @energy <= 0

      mass = Physics.mass_factor(radius)
      direction_multiplier = Physics.thrust_direction_multiplier(
        vx: @velocity_x, vy: @velocity_y,
        thrust_angle: angle, speed: self.speed
      )
      required_energy = Physics.thrust_cost(speed: speed, mass: mass, direction_multiplier: direction_multiplier)

      if @energy >= required_energy
        @energy -= required_energy
        actual_speed = speed
      else
        actual_speed = Physics.thrust_speed_from_energy(
          energy: @energy, mass: mass, direction_multiplier: direction_multiplier
        )
        @energy = 0
      end

      velocity = Physics.thrust_velocity(speed: actual_speed, angle: angle, mass: mass)
      adjust_velocity(velocity[:vx], velocity[:vy])
      true
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
