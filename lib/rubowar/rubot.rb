# frozen_string_literal: true

# [file]
# purpose = "Module that players include in their rubot classes"
# responsibility = "Provide action API, state access, and utility methods"
# pattern = "Mixin Module"
#
# [module.Rubot]
# purpose = "Base module for all player-created rubots"
# usage = "class MyBot; include Rubowar::Rubot; def act; ...; end; end"
#
# [design_note]
# This is a coding challenge - some aspects are intentionally left for players to discover:
# - Action return values indicate queueing success, not execution success
# - Energy costs are approximate for thrust (depends on momentum)
# - Players must budget energy across multiple actions in a single chronon
# - Sensing has 1-chronon latency (results available next turn)
# These design decisions create strategic depth and reward careful planning
#
# [actions]
# structure = "Actions are queued by phase: { sense: [], move: [], combat: [] }"
# processing = "All rubots queue actions in act(), then Battle processes phases simultaneously"
# return_values = "All action methods return true if queued, false if invalid params or insufficient energy"
#
# sense_phase = [
#   "probe(*attributes) -> bool - Check turret line for target (1-18 energy)",
#   "scan(angle:, distance:) -> bool - Arc scan from turret direction",
#   "pulse(distance:) -> bool - 360° radar ping around self",
#   "detect -> bool - Counter-intel: who scanned you this chronon (processed last)"
# ]
# move_phase = [
#   "thrust(speed:, angle:) -> bool - Apply thrust in direction (0°=east, 90°=north)",
#   "rotate_turret(degrees) -> bool - Rotate turret relative to current angle"
# ]
# combat_phase = [
#   "fire(energy) -> bool - Fire bullet, damage = energy * 1.5",
#   "raise_shields(energy) -> bool - Add to shield, absorbs damage, decays 12%/chronon"
# ]
#
# [state_access]
# self = ["x", "y", "velocity_x", "velocity_y", "speed", "health", "energy", "shield_level", "turret_angle"]
# arena = ["arena_width", "arena_height", "chronons", "energons", "live_rubot_count"]
# results = ["probe_echo", "scan_echo", "pulse_echo", "detect_intel"]
#
# [utilities]
# geometry = ["distance_to", "angle_to", "normalize_angle", "lead_position", "lead_angle"]
# awareness = ["near_wall?", "nearest_wall_distance", "nearest_wall", "wall_distance",
#              "approaching_wall?", "arena_diagonal", "find_nearest_energon", "energon_still_exists?"]
# momentum = ["velocity_angle", "momentum_aligned?"]
# energy = ["thrust_cost"]
#
# [callbacks]
# lifecycle = ["on_spawn", "on_death", "on_hit(damage, direction)", "on_wall", "on_collision(other)", "on_energon(amount)"]

require "forwardable"

module Rubowar
  module Rubot
    def self.included(klass)
      klass.extend(ClassMethods)
      klass.extend(Forwardable)

      # State accessors for game to set, rubots to read
      klass.attr_accessor :rubot_state, :arena_state, :actions

      # Sensing results from previous chronon (set by engine, read by rubot)
      # Write accessors for the engine to set results
      klass.attr_writer :probe_echo, :scan_echo, :pulse_echo, :detect_intel

      # Tracks energy committed to actions this chronon (reset by engine each chronon)
      klass.attr_accessor :_pending_energy_spend

      # Delegate rubot state accessors
      klass.def_delegators :rubot_state,
                           :x, :y, :velocity_x, :velocity_y, :speed,
                           :turret_angle,
                           :health, :energy, :shield_level,
                           :damage_dealt, :damage_taken, :size

      # Delegate arena state accessors
      klass.def_delegators :arena_state,
                           :arena_width, :arena_height, :friction, :chronon, :energons, :live_rubot_count,
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

    # Sensing result readers - return empty objects instead of nil for safer API
    # This eliminates the need for safe navigation (&.) when accessing results
    def probe_echo
      @probe_echo || ProbeEcho.empty
    end

    def scan_echo
      @scan_echo || ScanEcho.empty
    end

    def pulse_echo
      @pulse_echo || PulseEcho.empty
    end

    def detect_intel
      @detect_intel || DetectIntel.empty
    end

    # Action methods (queue for execution after act)
    #
    # IMPORTANT: All action methods return true/false to indicate if the action was QUEUED,
    # not whether it will succeed at execution time. Return values mean:
    #   true  = Action was queued and energy was reserved (upfront check passed)
    #   false = Action was NOT queued (insufficient energy or invalid parameters)
    #
    # Actions execute in phases (sense -> move -> combat) after all rubots call act().
    # An action may still partially fail at execution if conditions change (e.g., thrust
    # against momentum costs more than the reserved minimum).

    # Thrust in the specified direction (world coordinates, 0° = east, 90° = north).
    # Energy cost is calculated based on desired speed and momentum change:
    #   base_cost = (speed / 1.5)^2 * mass
    #   actual_cost = base_cost * direction_multiplier (1.0 to 2.0)
    #
    # The direction_multiplier depends on your current momentum at execution time:
    # - 1.0x when thrusting in same direction as current velocity
    # - 2.0x when thrusting opposite to current velocity
    #
    # If you can't afford the full thrust, you get partial thrust and energy drains to zero.
    # Returns true if action was queued (minimum energy reserved), false if insufficient energy.
    #
    # TIP: Use thrust_cost(speed:, angle:) to estimate the actual cost before committing.
    def thrust(speed:, angle:)
      min_cost = minimum_thrust_cost(speed)
      return false unless can_afford?(min_cost)

      commit_energy(min_cost)
      actions[:move] << { type: :thrust, speed:, angle: normalize_angle(angle) }
      true
    end

    # Rotate turret by the specified degrees (positive = counter-clockwise).
    # Returns true if action was queued, false if no rotation needed or insufficient energy.
    def rotate_turret(degrees)
      degrees = normalize_angle(degrees)
      return false if degrees.zero?

      cost = (degrees.abs / Config::Combat::TURRET_TURN_DIVISOR).ceil
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions[:move] << { type: :rotate_turret, degrees: }
      true
    end

    # Fire a bullet with the specified energy.
    # Returns true if action was queued, false if insufficient energy.
    def fire(energy_amount)
      return false unless can_afford?(energy_amount)

      commit_energy(energy_amount)
      actions[:combat] << { type: :fire, energy: energy_amount }
      true
    end

    # Add energy to shields.
    # Returns true if action was queued, false if insufficient energy.
    def raise_shields(energy_amount)
      return false unless can_afford?(energy_amount)

      commit_energy(energy_amount)
      actions[:combat] << { type: :shield, energy: energy_amount }
      true
    end

    # Queues a probe action. Returns true if enough energy, false otherwise.
    # Results from the previous chronon's probe are available via probe_echo.
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
    # Check probe_echo for data: { size:, x:, y:, velocity_x:, ... } or {} if no target
    def probe(*attributes)
      attributes = [:size] if attributes.empty?
      attributes = attributes.uniq # Remove duplicates to avoid double-charging

      invalid = attributes - Config::Sensing::PROBE_ATTRIBUTES
      raise ArgumentError, "Invalid probe attributes: #{invalid.join(", ")}" if invalid.any?

      cost = SensorCalculator.probe_cost(attributes)
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions[:sense] << { type: :probe, attributes: }
      true
    end

    # Queues a scan action. Returns true if enough energy, false otherwise.
    # Results from the previous chronon's scan are available via scan_echo.
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
    # Check scan_echo for data: [{ x:, y:, type: :rubot/:bullet, ... }, ...] or []
    def scan(angle:, distance:, velocity: false, owner: false)
      cost = SensorCalculator.scan_cost(angle:, distance:, velocity:, owner:)
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions[:sense] << { type: :scan, angle:, distance:, velocity:, owner: }
      true
    end

    # Queues a pulse action. Returns true if enough energy, false otherwise.
    # Results from the previous chronon's pulse are available via pulse_echo.
    #
    # Pulse performs an omnidirectional radar ping centered on the rubot.
    #
    # @param distance [Numeric] Radius of detection circle in units
    # @param owner [Boolean] Include owner info for bullets (+1 energy)
    #
    # Energy cost: 2 + ceil(distance/75) [+1 for owner]
    #
    # Check pulse_echo for data: [{ x:, y:, type: :rubot/:bullet, ... }, ...] or []
    def pulse(distance:, owner: false)
      cost = SensorCalculator.pulse_cost(distance:, owner:)
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions[:sense] << { type: :pulse, distance:, owner: }
      true
    end

    # Queues a detect action. Returns true if enough energy, false otherwise.
    #
    # Detect performs counter-intelligence: reports how many times you were
    # probed, scanned, and pulsed in the CURRENT chronon's sense phase.
    #
    # TIMING: Unlike probe/scan/pulse which return results from the PREVIOUS chronon,
    # detect returns results from the CURRENT chronon. It runs last in the sense phase
    # (after all probe/scan/pulse actions) so it can count sensing actions targeting you.
    # Results are available via detect_intel during the NEXT chronon's act() method.
    #
    # Energy cost: 2
    #
    # Check detect_intel for data: { probed: N, scanned: N, pulsed: N }
    def detect
      cost = SensorCalculator.detect_cost
      return false unless can_afford?(cost)

      commit_energy(cost)
      actions[:sense] << { type: :detect }
      true
    end

    # Callbacks (override in rubot class)
    def on_spawn; end
    def on_hit(damage:, direction:); end
    def on_death; end
    def on_wall; end
    def on_collision(other_rubot); end
    def on_energon(amount); end

    # Required method for rubots to implement
    def act
      raise NotImplementedError, "Rubot must implement #act method"
    end

    # === Utility methods (available to all rubots) ===

    # Calculate distance to a point
    def distance_to(target_x:, target_y:)
      Physics.distance(x1: x, y1: y, x2: target_x, y2: target_y)
    end

    # Calculate angle to a point (in degrees, 0° = east, 90° = north)
    def angle_to(target_x:, target_y:)
      Math.atan2(target_y - y, target_x - x) * 180 / Math::PI
    end

    # Normalize angle to -180..180 range (180 is preferred over -180)
    # Use this for calculating shortest angular difference or for clamping angles.
    def normalize_angle(angle)
      Physics.normalize_angle(angle)
    end

    # Check if a tracked energon still exists at its position
    # Uses tolerance for float comparison safety
    def energon_still_exists?(target)
      return false unless target

      energons.any? do |e|
        (e[:x] - target[:x]).abs < Config::Sensing::MIN_MEASURABLE_DISTANCE &&
          (e[:y] - target[:y]).abs < Config::Sensing::MIN_MEASURABLE_DISTANCE
      end
    end

    # Find the closest energon within optional max_distance
    def find_nearest_energon(max_distance: nil)
      return nil if energons.empty?

      candidates = energons
      candidates = candidates.select { |e| distance_to(target_x: e[:x], target_y: e[:y]) <= max_distance } if max_distance

      return nil if candidates.empty?

      candidates.min_by { |e| distance_to(target_x: e[:x], target_y: e[:y]) }
    end

    # Calculate lead position for shooting a moving target
    # Returns [lead_x, lead_y] - where to aim to hit target
    # @param target_x - current target x position
    # @param target_y - current target y position
    # @param velocity_x - target x velocity (nil if unknown)
    # @param velocity_y - target y velocity (nil if unknown)
    # @param projectile_speed - speed of bullet (default: Config::Targeting::BULLET_SPEED)
    # @param max_lead_chronons - cap on prediction distance (default: Config::Targeting::MAX_LEAD_CHRONONS)
    def lead_position(target_x:, target_y:, velocity_x:, velocity_y:,
                      projectile_speed: Config::Targeting::BULLET_SPEED,
                      max_lead_chronons: Config::Targeting::MAX_LEAD_CHRONONS,
                      friction: Config::Arena::DEFAULT_FRICTION)
      return [target_x, target_y] unless velocity_x && velocity_y

      dist = distance_to(target_x:, target_y:)
      lead_chronons = [dist / projectile_speed, max_lead_chronons].min

      # Account for friction: target decelerates each chronon
      # Displacement = v * (1 - friction^t) / (1 - friction) for geometric series
      if friction < 1.0 && lead_chronons > 0
        displacement_factor = (1 - (friction**lead_chronons)) / (1 - friction)
      else
        displacement_factor = lead_chronons
      end

      lead_x = target_x + (velocity_x * displacement_factor)
      lead_y = target_y + (velocity_y * displacement_factor)

      margin = Config::Movement::DEFAULT_ARENA_MARGIN
      # Clamp to arena bounds
      [
        lead_x.clamp(margin, arena_width - margin),
        lead_y.clamp(margin, arena_height - margin)
      ]
    end

    # Calculate angle to lead position (for aiming turret at moving target)
    def lead_angle(target_x:, target_y:, velocity_x:, velocity_y:,
                   projectile_speed: Config::Targeting::BULLET_SPEED,
                   friction: Config::Arena::DEFAULT_FRICTION)
      lead_x, lead_y = lead_position(target_x:, target_y:, velocity_x:, velocity_y:,
                                     projectile_speed:, friction:)
      angle_to(target_x: lead_x, target_y: lead_y)
    end

    # Clamp coordinates to stay within arena bounds
    # @param target_x - x coordinate to clamp
    # @param target_y - y coordinate to clamp
    # @param margin - distance from walls (default: Config::Movement::DEFAULT_ARENA_MARGIN)
    def clamp_to_arena(target_x:, target_y:, margin: Config::Movement::DEFAULT_ARENA_MARGIN)
      [
        target_x.clamp(margin, arena_width - margin),
        target_y.clamp(margin, arena_height - margin)
      ]
    end

    # Calculate speed from velocity components
    def speed_from_velocity(velocity_x:, velocity_y:)
      return 0 unless velocity_x && velocity_y

      Math.sqrt((velocity_x**2) + (velocity_y**2))
    end

    # Get distance to nearest wall
    def nearest_wall_distance
      [x, arena_width - x, y, arena_height - y].min
    end

    # Check if position is near any wall
    def near_wall?(buffer = Config::Movement::DEFAULT_WALL_BUFFER)
      nearest_wall_distance < buffer
    end

    # Get which wall is nearest (:left, :right, :bottom, :top)
    def nearest_wall
      distances = { left: x, right: arena_width - x, bottom: y, top: arena_height - y }
      distances.min_by { |_, d| d }.first
    end

    # Get distance to wall in a specific direction (RoboWar WALL style)
    # @param angle - direction in degrees (0=east, 90=north, 180=west, 270=south)
    # Returns distance to wall if traveling in that direction
    def wall_distance(angle)
      radians = angle * Math::PI / 180
      dx = Math.cos(radians)
      dy = Math.sin(radians)

      # Calculate distance to each wall in this direction
      # Use Float::EPSILON to avoid division by near-zero from floating point artifacts
      # (e.g., cos(90°) returns 6.12e-17, not exactly 0)
      distances = []
      distances << ((arena_width - x) / dx) if dx > Float::EPSILON    # right wall
      distances << (-x / dx) if dx < -Float::EPSILON                  # left wall
      distances << ((arena_height - y) / dy) if dy > Float::EPSILON   # top wall
      distances << (-y / dy) if dy < -Float::EPSILON                  # bottom wall

      distances.min || Float::INFINITY
    end

    # Check if current velocity is carrying us toward a wall
    # @param buffer - distance from wall to consider "approaching"
    # Returns true if momentum will hit a wall within buffer distance
    def approaching_wall?(buffer = Config::Movement::DEFAULT_APPROACH_BUFFER)
      return false if speed < Config::Movement::STATIONARY_THRESHOLD

      (x < buffer && velocity_x.negative?) ||
        (x > arena_width - buffer && velocity_x.positive?) ||
        (y < buffer && velocity_y.negative?) ||
        (y > arena_height - buffer && velocity_y.positive?)
    end

    # Get current movement direction in degrees (from velocity)
    # Returns nil if stationary
    def velocity_angle
      return nil if speed < Config::Movement::VELOCITY_ANGLE_THRESHOLD

      Math.atan2(velocity_y, velocity_x) * 180 / Math::PI
    end

    # Check if current momentum is aligned with desired direction
    # @param desired_angle - direction we want to go (degrees)
    # @param tolerance - how many degrees off is acceptable
    # Returns true if velocity is within tolerance of desired angle
    def momentum_aligned?(desired_angle, tolerance: Config::Movement::DEFAULT_ALIGNMENT_TOLERANCE)
      return true if speed < Config::Movement::STATIONARY_THRESHOLD

      current = velocity_angle
      return true unless current

      diff = normalize_angle(desired_angle - current).abs
      diff <= tolerance
    end

    # Get arena diagonal (useful for scaling distances to arena size)
    def arena_diagonal
      Math.sqrt((arena_width**2) + (arena_height**2))
    end

    # Calculate estimated thrust energy cost based on current momentum
    # Delegates to Physics.thrust_cost for consistency with execution.
    #
    # The cost depends on how aligned the thrust is with your current velocity:
    # - Thrusting with momentum (same direction): 1.0x base cost
    # - Thrusting perpendicular: 1.5x base cost
    # - Thrusting against momentum (opposite direction): 2.0x base cost
    #
    # @param thrust_speed [Numeric] Desired thrust speed
    # @param angle [Numeric] Thrust direction in degrees (0° = east, 90° = north)
    # @return [Integer] Estimated energy cost
    #
    # @example
    #   cost = thrust_cost(thrust_speed: 6, angle: 90)
    #   if cost <= energy
    #     thrust(speed: 6, angle: 90)
    #   end
    def thrust_cost(thrust_speed:, angle:)
      mass = Physics.mass_factor(Config::Rubot::SIZES[size][:radius])
      direction_multiplier = Physics.thrust_direction_multiplier(
        vx: velocity_x, vy: velocity_y, thrust_angle: angle, speed:
      )
      Physics.thrust_cost(speed: thrust_speed, mass:, direction_multiplier:)
    end

    private

    # Returns energy available for actions this chronon
    # This accounts for energy already committed to queued actions
    def available_energy
      energy - (@_pending_energy_spend || 0)
    end

    # Checks if we can afford a given energy cost
    # @param cost [Numeric] Energy cost of the action
    # @return [Boolean] true if we have enough available energy
    def can_afford?(cost)
      available_energy >= cost
    end

    # Commits energy to an action (reserves it from the available pool)
    # This prevents over-committing energy across multiple queued actions
    # @param cost [Numeric] Energy cost to reserve
    def commit_energy(cost)
      @_pending_energy_spend = (@_pending_energy_spend || 0) + cost
    end

    # Minimum thrust cost (assumes best-case 1.0x direction multiplier)
    # Used internally for action queueing validation
    def minimum_thrust_cost(speed)
      radius = Config::Rubot::SIZES[size][:radius]
      mass = Physics.mass_factor(radius)
      base_cost = (speed / Config::Physics::THRUST_MULTIPLIER)**2
      (base_cost * mass * Config::Physics::MIN_DIRECTION_MULTIPLIER).ceil
    end
  end
end
