# frozen_string_literal: true

require "forwardable"

module Rubowar
  module Rubot
    def self.included(klass)
      klass.extend(ClassMethods)
      klass.extend(Forwardable)
      klass.include(SensingCosts)

      # State accessors for game to set, rubots to read
      klass.attr_accessor :rubot_state, :arena_state, :actions

      # Sensing results from previous tick (set by engine, read by rubot)
      klass.attr_accessor :probe_result, :scan_result, :pulse_result, :detect_result

      # Tracks energy committed to actions this tick (reset by engine each tick)
      klass.attr_accessor :_pending_energy_spend

      # Delegate rubot state accessors
      klass.def_delegators :rubot_state,
                           :x, :y, :velocity_x, :velocity_y, :speed,
                           :turret_angle,
                           :health, :energy, :shield_level,
                           :damage_dealt, :damage_taken, :size

      # Delegate arena state accessors
      klass.def_delegators :arena_state,
                           :arena_width, :arena_height, :friction, :tick_number, :energons, :live_rubot_count,
                           :energon_spawn_interval, :energon_growth_rate
    end

    module ClassMethods
      def size(value = nil)
        if value
          unless RubotRunner::SIZES.key?(value)
            raise ArgumentError, "Invalid size: #{value}. Must be one of: #{RubotRunner::SIZES.keys.join(', ')}"
          end

          @_size = value
        else
          @_size || :medium
        end
      end
    end

    # Action methods (queue for execution after tick)

    # Thrust in the specified direction (world coordinates, 0° = east, 90° = north).
    # Energy cost is calculated based on desired speed and momentum change:
    #   base_cost = (speed / 1.5)^2
    #   actual_cost = base_cost * momentum_multiplier (1.0 to 2.0)
    #
    # If you can't afford the full thrust, you get partial thrust and energy drains to zero.
    def thrust(speed:, angle:)
      return if speed <= 0

      actions << { type: :thrust, speed: speed, angle: angle % 360 }
    end

    def turret(degrees)
      degrees = normalize_degrees(degrees)
      return if degrees == 0

      actions << { type: :turret, degrees: degrees }
    end

    def fire(energy_amount)
      return if energy_amount <= 0

      actions << { type: :fire, energy: energy_amount }
    end

    def shield(energy_amount)
      return if energy_amount <= 0

      actions << { type: :shield, energy: energy_amount }
    end

    PROBE_ATTRIBUTES = %i[size position velocity turret_angle shield health energy].freeze

    # Queues a probe action. Returns true if enough energy, false otherwise.
    # Results from the previous tick's probe are available via probe_result.
    #
    # Probe with no arguments defaults to :size (1 energy) - a detection ping that
    # tells you something is there and its size, but not where.
    #
    # Available attributes:
    #   :size         - 1 energy (small/medium/large) - detection ping
    #   :position     - 4 energy (x, y coordinates)
    #   :velocity     - 3 energy (velocity_x, velocity_y) - motion detector
    #   :turret_angle - 2 energy (where their turret is pointing)
    #   :shield       - 2 energy (shield_level)
    #   :health       - 3 energy (current HP)
    #   :energy       - 3 energy (current energy)
    #
    # Examples:
    #   probe                              # 1 energy  -> true/false
    #   probe(:position)                   # 4 energy  -> true/false
    #   probe(:position, :velocity)        # 7 energy  -> true/false
    #
    # Check probe_result for data: { size:, x:, y:, velocity_x:, ... } or {} if no target
    def probe(*attributes)
      attributes = [:size] if attributes.empty?

      invalid = attributes - PROBE_ATTRIBUTES
      raise ArgumentError, "Invalid probe attributes: #{invalid.join(', ')}" if invalid.any?

      cost = probe_cost(attributes)
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions << { type: :probe, attributes: attributes }
      true
    end

    # Queues a scan action. Returns true if enough energy, false otherwise.
    # Results from the previous tick's scan are available via scan_result.
    #
    # Scan performs an arc scan centered on the turret direction.
    #
    # @param angle [Numeric] Arc width in degrees (centered on turret direction)
    # @param distance [Numeric] Maximum range (radius) in units
    # @param velocity [Boolean] Include velocity data (+2 energy)
    # @param owner [Boolean] Include owner info for bullets (+1 energy)
    #
    # Energy cost: 3 + ceil(angle/20) + ceil(distance/100) [+2 for velocity] [+1 for owner]
    #
    # Check scan_result for data: [{ x:, y:, type: :rubot/:bullet, ... }, ...] or []
    def scan(angle:, distance:, velocity: false, owner: false)
      raise ArgumentError, "angle must be positive" if angle <= 0
      raise ArgumentError, "distance must be positive" if distance <= 0

      cost = scan_cost(angle: angle, distance: distance, velocity: velocity, owner: owner)
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions << { type: :scan, angle: angle, distance: distance, velocity: velocity, owner: owner }
      true
    end

    # Queues a pulse action. Returns true if enough energy, false otherwise.
    # Results from the previous tick's pulse are available via pulse_result.
    #
    # Pulse performs an omnidirectional radar ping centered on the rubot.
    #
    # @param distance [Numeric] Radius of detection circle in units
    # @param owner [Boolean] Include owner info for bullets (+1 energy)
    #
    # Energy cost: 2 + ceil(distance/75) [+1 for owner]
    #
    # Check pulse_result for data: [{ x:, y:, type: :rubot/:bullet, ... }, ...] or []
    def pulse(distance:, owner: false)
      raise ArgumentError, "distance must be positive" if distance <= 0

      cost = pulse_cost(distance: distance, owner: owner)
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions << { type: :pulse, distance: distance, owner: owner }
      true
    end

    # Queues a detect action. Returns true if enough energy, false otherwise.
    # Results are available via detect_result after the sense phase completes.
    #
    # Detect performs counter-intelligence: reports how many times you were
    # probed, scanned, and pulsed in the current tick's sense phase.
    #
    # Energy cost: 2
    #
    # Check detect_result for data: { probed: N, scanned: N, pulsed: N }
    def detect
      cost = detect_cost
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions << { type: :detect }
      true
    end

    # Callbacks (override in rubot class)
    def on_spawn; end
    def on_hit(damage, direction); end
    def on_death; end
    def on_wall; end
    def on_collision(other_rubot); end
    def on_energon(amount); end

    # Required method for rubots to implement
    def tick
      raise NotImplementedError, "Rubot must implement #tick method"
    end

    private

    # Returns energy available for actions this tick
    def available_energy
      energy - (@_pending_energy_spend || 0)
    end

    # Checks if we can afford a given energy cost
    def can_afford?(cost)
      available_energy >= cost
    end

    # Commits energy to an action (tracks pending spend)
    def commit_energy(cost)
      @_pending_energy_spend = (@_pending_energy_spend || 0) + cost
    end

    # Normalize degrees to -180..180 range (shortest turn)
    def normalize_degrees(degrees)
      degrees = degrees % 360
      degrees -= 360 if degrees > 180
      degrees += 360 if degrees < -180
      degrees
    end
  end
end
