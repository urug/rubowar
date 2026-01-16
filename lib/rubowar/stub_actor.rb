# frozen_string_literal: true

require "securerandom"

# [file]
# purpose = "Stub actor for testing and external source integration"
# responsibility = "Implements actor duck type interface without a rubot instance"
# pattern = "Test Double / Adapter"
#
# [class.StubActor]
# purpose = "Lightweight actor for external/remote sources"
# note = "Unlike RubotActor which wraps a Rubot, StubActor has no rubot instance"
# usage = "Actions are set directly via set_actions(), act() is a no-op"
# use_cases = [
#   "Testing Battle's duck type interface",
#   "Simulating network/remote actors",
#   "Reference implementation for custom actors"
# ]

module Rubowar
  class StubActor
    attr_accessor :x, :y, :velocity_x, :velocity_y, :turret_angle
    attr_accessor :health, :energy, :shield_level
    attr_accessor :damage_dealt, :damage_taken
    attr_accessor :death_processed, :_act_completed
    attr_reader :id, :size, :detection_counts, :position_set

    def initialize(size: :medium, health: nil, energy: nil)
      validate_size!(size)

      @id = SecureRandom.uuid
      @size = size
      @x = 0.0
      @y = 0.0
      @velocity_x = 0.0
      @velocity_y = 0.0
      @turret_angle = 0.0
      @health = health || max_health
      @energy = energy || max_energy
      @shield_level = 0
      @damage_dealt = 0
      @damage_taken = 0
      @death_processed = false
      @_act_completed = false
      @detection_counts = { probed: 0, scanned: 0, pulsed: 0 }
      @position_set = false
      @_actions = { sense: [], move: [], combat: [] }
      @_sensing_results = {}
    end

    # === Configuration (read-only) ===

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
      max_health
    end

    def speed
      Math.sqrt((@velocity_x**2) + (@velocity_y**2))
    end

    # === State Query ===

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

    # === Identity (for Battle compatibility) ===

    def rubot_class
      @_mock_class ||= Class.new do
        def self.name
          "StubActor"
        end
      end
    end

    def instance
      self
    end

    # === Action Management ===

    def rubot_actions
      @_actions
    end

    def reset_actions
      @_actions = { sense: [], move: [], combat: [] }
    end

    def act
      # No-op: actions are set externally via set_actions
    end

    # Test helper: pre-set actions that will be processed by Battle phases
    def set_actions(sense: [], move: [], combat: [])
      @_actions = { sense: sense, move: move, combat: combat }
    end

    # === State Setup (called by Battle each chronon) ===

    def rubot_state=(state)
      @_rubot_state = state
    end

    def arena_state=(state)
      @_arena_state = state
    end

    def _pending_energy_spend=(amount)
      @_pending_energy_spend = amount
    end

    # === Damage & Health ===

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

    # === Energy Management ===

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

    # === Physics ===

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

    def adjust_velocity(dvx:, dvy:)
      @velocity_x += dvx
      @velocity_y += dvy
    end

    def adjust_position(dx:, dy:)
      @x += dx
      @y += dy
    end

    def clamp_x(min:, max:)
      @x = @x.clamp(min, max)
    end

    def clamp_y(min:, max:)
      @y = @y.clamp(min, max)
    end

    def apply_friction(friction)
      @velocity_x *= friction
      @velocity_y *= friction
    end

    # === Turret & Combat ===

    def set_turret_angle(angle)
      @turret_angle = Physics.normalize_angle(angle)
    end

    def turn_turret(degrees)
      cost = (degrees.abs / Config::Combat::TURRET_TURN_DIVISOR).ceil
      return false unless spend_energy(cost)

      @turret_angle = Physics.normalize_angle(@turret_angle + degrees)
      true
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

    def add_damage_dealt(amount)
      @damage_dealt += amount
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

    # === Detection & Sensing ===

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

    def set_sensing_results(probe: nil, scan: nil, pulse: nil, detect: nil)
      @_sensing_results[:probe] = ProbeEcho.from_hash(probe) unless probe.nil?
      @_sensing_results[:scan] = ScanEcho.new(scan) unless scan.nil?
      @_sensing_results[:pulse] = PulseEcho.new(pulse) unless pulse.nil?
      @_sensing_results[:detect] = DetectIntel.from_hash(detect) unless detect.nil?
    end

    # Sensing result accessors (for compatibility with rubot instance pattern)
    def probe_echo
      @_sensing_results[:probe]
    end

    def scan_echo
      @_sensing_results[:scan]
    end

    def pulse_echo
      @_sensing_results[:pulse]
    end

    def detect_intel
      @_sensing_results[:detect]
    end

    # === Callbacks ===

    def call_safely
      return nil unless alive?

      yield self
    rescue StandardError => e
      apply_collision_damage(Config::Battle::ERROR_DAMAGE)
      warn "[StubActor] Error in callback: #{e.class} - #{e.message}"
      nil
    end

    def call_on_death
      # No-op for stub: no rubot instance to call
    end

    # Callback stubs (for call_safely compatibility)
    def on_spawn; end
    def on_hit(damage:, direction:); end
    def on_wall; end
    def on_collision(other_state); end
    def on_energon(amount); end
    def on_death; end

    private

    def validate_size!(size)
      return if Config::Rubot::SIZES.key?(size)

      valid_sizes = Config::Rubot::SIZES.keys.join(", ")
      raise InvalidRubotSizeError, "Invalid stub actor size '#{size}'. Must be one of: #{valid_sizes}"
    end
  end
end
