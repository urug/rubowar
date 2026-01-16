# frozen_string_literal: true

require "forwardable"
require "securerandom"

# [file]
# purpose = "Internal mutable state tracker for the game engine"
# responsibility = "Track position, health, energy, and stats for each rubot"
# pattern = "State Container"
#
# [class.RubotActor]
# purpose = "Wraps a Rubot instance with mutable game state"
# note = "Players never interact with this directly - they get immutable RubotState snapshots"
# validation = "Raises InvalidRubotSizeError if rubot class has invalid size"
# collaborators = ["Arena", "Battle", "RubotState"]
#
# [sizes]
# small = { radius: 16, energy_regen: 8, max_health: 80 }
# medium = { radius: 20, energy_regen: 10, max_health: 100 }
# large = { radius: 24, energy_regen: 12, max_health: 120 }
# tradeoffs = "Small = agile, cheap thrust. Large = tanky, high regen, harder to hit"
#
# [damage_methods]
# apply_damage = "Normal damage, shields absorb first"
# apply_collision_damage = "Physical impact, bypasses shields"
#
# [callback_methods]
# call_safely = "Block-based callback with error handling"
# examples = [
#   "actor.call_safely(&:on_spawn)                                    # No args",
#   "actor.call_safely { |bot| bot.on_hit(damage: 10, direction: 45) } # With args"
# ]

module Rubowar
  class RubotActor
    extend Forwardable
    attr_accessor :x, :y, :velocity_x, :velocity_y, :turret_angle, :health, :energy, :shield_level, :damage_dealt,
                  :damage_taken, :death_processed, :_act_completed
    attr_reader :id, :size, :rubot_class, :instance, :detection_counts, :position_set
    def_delegators :@instance, :act, :rubot_state=, :arena_state=, :_pending_energy_spend=
    def_delegator :@instance, :actions, :rubot_actions

    def initialize(rubot_class)
      # Validate size before setting any instance variables to avoid partial initialization
      size = rubot_class.size
      validate_size!(size, rubot_class)

      @id = SecureRandom.uuid
      @rubot_class = rubot_class
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
      Config::Rubot::MAX_ENERGY
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
      NumericValidation.validate!(amount, name: "energy amount", non_negative: true)

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

    def set_position(x:, y:)
      @x = x
      @y = y
      @position_set = true
    end

    def set_velocity(vx:, vy:)
      @velocity_x = vx
      @velocity_y = vy
    end

    def set_turret_angle(angle)
      @turret_angle = Physics.normalize_angle(angle)
    end

    def clamp_x(min:, max:)
      @x = @x.clamp(min, max)
    end

    def clamp_y(min:, max:)
      @y = @y.clamp(min, max)
    end

    def add_damage_dealt(amount)
      @damage_dealt += amount
    end

    def add_energy(amount)
      @energy = [@energy + amount, max_energy].min
    end

    def adjust_velocity(dvx:, dvy:)
      @velocity_x += dvx
      @velocity_y += dvy
    end

    def adjust_position(dx:, dy:)
      @x += dx
      @y += dy
    end

    def add_shield(amount)
      @shield_level = [@shield_level + amount, max_shield].min
    end

    def process_detect
      return false unless spend_energy(SensorCalculator.detect_cost)

      set_sensing_results(detect: @detection_counts.dup.freeze)
      true
    end

    # Reset the rubot's actions hash for a new chronon
    def reset_actions
      @instance.actions = { sense: [], move: [], combat: [] }
    end

    # Set sensing results on the rubot instance (encapsulates internal access)
    # Results are wrapped in structured Data classes for better API ergonomics.
    # @param probe [Hash, nil] Probe result to set (wrapped in ProbeEcho)
    # @param scan [Array, nil] Scan results to set (wrapped in ScanEcho)
    # @param pulse [Array, nil] Pulse results to set (wrapped in PulseEcho)
    # @param detect [Hash, nil] Detect results to set (wrapped in DetectIntel)
    def set_sensing_results(probe: nil, scan: nil, pulse: nil, detect: nil)
      @instance.probe_echo = ProbeEcho.from_hash(probe) unless probe.nil?
      @instance.scan_echo = ScanEcho.new(scan) unless scan.nil?
      @instance.pulse_echo = PulseEcho.new(pulse) unless pulse.nil?
      @instance.detect_intel = DetectIntel.from_hash(detect) unless detect.nil?
    end

    def turn_turret(degrees)
      cost = (degrees.abs / Config::Combat::TURRET_TURN_DIVISOR).ceil
      return false unless spend_energy(cost)

      @turret_angle = Physics.normalize_angle(@turret_angle + degrees)
      true
    end

    def increase_shielding(energy)
      NumericValidation.validate!(energy, name: "shield energy", positive: true)

      return false unless spend_energy(energy)

      add_shield(energy)
      true
    end

    def thrust(speed:, angle:)
      NumericValidation.validate!(speed, name: "thrust speed", positive: true)
      NumericValidation.validate!(angle, name: "thrust angle")

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
      adjust_velocity(dvx: velocity[:vx], dvy: velocity[:vy])
      true
    end

    # Safely execute a block with the rubot instance, penalizing errors with damage
    # Preferred over safe_callback for better type safety and IDE support
    #
    # @yield [instance] Block receives the rubot instance
    # @return [Object, nil] Block return value or nil on error/dead
    #
    # @example
    #   actor.call_safely { |bot| bot.on_hit(damage: 10, direction: 45) }
    #   actor.call_safely { |bot| bot.on_collision(other_state) }
    def call_safely
      return nil unless alive?

      yield @instance
    rescue StandardError => e
      apply_collision_damage(Config::Battle::ERROR_DAMAGE)
      warn "[#{@rubot_class.name}] Error in callback: #{e.class} - #{e.message}"
      nil
    end

    # Call on_death callback for dead rubots.
    # Unlike call_safely, this doesn't check alive? since it's meant for death callbacks.
    # Errors are logged but don't apply damage (actor is already dead).
    def call_on_death
      @instance.on_death if @instance.respond_to?(:on_death)
    rescue StandardError => e
      warn "[#{@rubot_class.name}] Error in on_death callback: #{e.class} - #{e.message}"
      nil
    end

    private

    def validate_size!(size, rubot_class)
      return if Config::Rubot::SIZES.key?(size)

      valid_sizes = Config::Rubot::SIZES.keys.join(", ")
      raise InvalidRubotSizeError, "Invalid rubot size '#{size}' for #{rubot_class.name}. " \
                                   "Must be one of: #{valid_sizes}"
    end
  end
end
