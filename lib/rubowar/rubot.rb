# frozen_string_literal: true

# [file]
# purpose = "Module that players include in their rubot classes"
# responsibility = "Provide action API, state access, and utility methods"
# pattern = "Mixin Module"
#
# [module.Rubot]
# purpose = "Base module for all player-created rubots"
# usage = "class MyBot; include Rubowar::Rubot; def tick; ...; end; end"
#
# [actions]
# movement = [
#   "thrust(speed:, angle:) - Apply thrust in direction (0°=east, 90°=north)",
#   "turret(degrees) - Rotate turret relative to current angle"
# ]
# combat = [
#   "fire(energy) - Fire bullet, damage = energy * 1.5",
#   "shield(energy) - Add to shield, absorbs damage, decays 12%/tick"
# ]
# sensing = [
#   "probe(*attributes) - Check turret line for target (1-16 energy)",
#   "scan(angle:, distance:) - Arc scan from turret direction",
#   "pulse(distance:) - 360° radar ping around self",
#   "detect - Counter-intel: who scanned you this tick"
# ]
#
# [state_access]
# self = ["x", "y", "velocity_x", "velocity_y", "speed", "health", "energy", "shield_level", "turret_angle"]
# arena = ["arena_width", "arena_height", "tick_number", "energons", "live_rubot_count"]
# results = ["probe_result", "scan_result", "pulse_result", "detect_result"]
#
# [utilities]
# geometry = ["distance_to", "angle_to", "normalize_angle", "lead_position", "lead_angle"]
# awareness = ["near_wall?", "nearest_wall_distance", "find_nearest_energon", "energon_still_exists?"]
#
# [callbacks]
# lifecycle = ["on_spawn", "on_death", "on_hit(damage, direction)", "on_wall", "on_collision(other)", "on_energon(amount)"]

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
          raise ArgumentError, "Invalid size: #{value}. Must be one of: #{Config::Rubot::SIZES.keys.join(", ")}" unless Config::Rubot::SIZES.key?(value)

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

      actions << { type: :thrust, speed:, angle: angle % 360 }
    end

    def turret(degrees)
      degrees = normalize_degrees(degrees)
      return if degrees.zero?

      actions << { type: :turret, degrees: }
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
    # Available attributes (cost in energy):
    #   :size         - 1 energy - returns size symbol (small/medium/large)
    #   :turret_angle - 2 energy - returns turret angle in degrees
    #   :shield       - 2 energy - returns shield_level
    #   :velocity     - 3 energy - returns velocity_x, velocity_y
    #   :health       - 3 energy - returns current HP
    #   :energy       - 3 energy - returns current energy
    #   :position     - 4 energy - returns x, y coordinates
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
      raise ArgumentError, "Invalid probe attributes: #{invalid.join(", ")}" if invalid.any?

      cost = probe_cost(attributes)
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions << { type: :probe, attributes: }
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

      cost = scan_cost(angle:, distance:, velocity:, owner:)
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions << { type: :scan, angle:, distance:, velocity:, owner: }
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

      cost = pulse_cost(distance:, owner:)
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions << { type: :pulse, distance:, owner: }
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

    # === Utility methods (available to all rubots) ===

    # Calculate distance to a point
    def distance_to(target_x, target_y)
      Math.sqrt(((target_x - x)**2) + ((target_y - y)**2))
    end

    # Calculate angle to a point (in degrees, 0° = east, 90° = north)
    def angle_to(target_x, target_y)
      Math.atan2(target_y - y, target_x - x) * 180 / Math::PI
    end

    # Normalize angle to -180..180 range
    def normalize_angle(angle)
      angle %= 360
      angle -= 360 if angle > 180
      angle += 360 if angle < -180
      angle
    end

    # Check if a tracked energon still exists at its position
    def energon_still_exists?(target)
      return false unless target

      energons.any? { |e| e[:x] == target[:x] && e[:y] == target[:y] }
    end

    # Find the closest energon within optional max_distance
    def find_nearest_energon(max_distance: nil)
      return nil if energons.empty?

      candidates = energons
      candidates = candidates.select { |e| distance_to(e[:x], e[:y]) <= max_distance } if max_distance

      return nil if candidates.empty?

      candidates.min_by { |e| distance_to(e[:x], e[:y]) }
    end

    # Calculate lead position for shooting a moving target
    # Returns [lead_x, lead_y] - where to aim to hit target
    # @param target_x, target_y - current target position
    # @param velocity_x, velocity_y - target velocity (nil if unknown)
    # @param projectile_speed - speed of bullet (default: 18, the game's bullet speed)
    # @param max_lead_ticks - cap on prediction distance (default: 15)
    def lead_position(target_x, target_y, velocity_x, velocity_y, projectile_speed: 18, max_lead_ticks: 15)
      return [target_x, target_y] unless velocity_x && velocity_y

      dist = distance_to(target_x, target_y)
      lead_ticks = [dist / projectile_speed, max_lead_ticks].min

      lead_x = target_x + (velocity_x * lead_ticks)
      lead_y = target_y + (velocity_y * lead_ticks)

      # Clamp to arena bounds
      [
        lead_x.clamp(20, arena_width - 20),
        lead_y.clamp(20, arena_height - 20)
      ]
    end

    # Calculate angle to lead position (for aiming turret at moving target)
    def lead_angle(target_x, target_y, velocity_x, velocity_y, projectile_speed: 18)
      lead_x, lead_y = lead_position(target_x, target_y, velocity_x, velocity_y, projectile_speed:)
      angle_to(lead_x, lead_y)
    end

    # Clamp coordinates to stay within arena bounds
    # @param margin - distance from walls (default: 20, roughly rubot radius)
    def clamp_to_arena(target_x, target_y, margin: 20)
      [
        target_x.clamp(margin, arena_width - margin),
        target_y.clamp(margin, arena_height - margin)
      ]
    end

    # Calculate speed from velocity components
    def speed_from_velocity(velocity_x, velocity_y)
      return 0 unless velocity_x && velocity_y

      Math.sqrt((velocity_x**2) + (velocity_y**2))
    end

    # Get distance to nearest wall
    def nearest_wall_distance
      [x, arena_width - x, y, arena_height - y].min
    end

    # Check if position is near any wall
    def near_wall?(buffer = 50)
      nearest_wall_distance < buffer
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
      degrees %= 360
      degrees -= 360 if degrees > 180
      degrees += 360 if degrees < -180
      degrees
    end
  end
end
