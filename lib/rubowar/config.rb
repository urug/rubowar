# frozen_string_literal: true

# [file]
# purpose = "Centralized game configuration constants"
# responsibility = "Single source of truth for all game balance values"
# pattern = "Configuration Module"
#
# [organization]
# Config::Arena = "Arena dimensions, friction, spawn settings"
# Config::Physics = "Collision damage, wall bouncing, thrust mechanics"
# Config::Combat = "Fire damage, turret turning, bullet properties"
# Config::Rubot = "Size definitions, energy, shields"
# Config::Energon = "Pickup radius, value growth"
# Config::Battle = "Game loop settings, chronon timeout"
# Config::Sensing = "Probe, scan, pulse, detect costs, measurement thresholds"
# Config::Targeting = "SimpleTargeting defaults"

module Rubowar
  module Config
    module Arena
      DEFAULT_WIDTH = 640                # Arena width in units
      DEFAULT_HEIGHT = 640               # Arena height in units

      # Friction coefficient applied each chronon: velocity *= FRICTION
      # 0.92 means 8% speed loss per chronon; terminal velocity naturally emerges
      DEFAULT_FRICTION = 0.92

      # Spawn distance ratios (relative to arena dimensions)
      # These ensure rubots start with space to maneuver but close enough to engage
      SPAWN_WALL_BUFFER_RATIO = 0.08     # 8% of smaller dimension from walls
      SPAWN_MIN_DISTANCE_RATIO = 0.12    # 12% of diagonal between rubots (prevents spawn kills)
      SPAWN_MAX_DISTANCE_RATIO = 0.50    # 50% of diagonal max (ensures engagement range)

      # Energon spawn settings
      ENERGON_WALL_BUFFER_RATIO = 0.15   # 15% of smaller dimension (spawns away from edges)
      ENERGON_SPAWN_INTERVAL = 50        # Chronons between energon spawns
    end

    module Physics
      # Collision damage formula: BASE + (mass × speed × VELOCITY_MULTIPLIER)
      # Example: Medium bot at speed 10 = 2 + (1.0 × 10 × 0.5) = 7 damage
      COLLISION_BASE_DAMAGE = 2
      COLLISION_VELOCITY_MULTIPLIER = 0.5

      # Elasticity: 0 = inelastic (stick together), 1 = elastic (full bounce)
      COLLISION_ELASTICITY = 0.5         # Bot-bot: moderate bounce
      WALL_ELASTICITY = 0.2              # Walls: sticky, absorbs momentum

      # Walls act as heavy immovable objects for collision physics
      # Value of 24 makes walls ~17x heavier than large bot (mass 1.44), ensuring
      # walls are effectively immovable while still allowing physics-based bouncing.
      # (Coincidentally same number as large bot radius, but different units)
      WALL_MASS = 24.0

      # Thrust cost formula: (speed / THRUST_MULTIPLIER)² × mass × direction_multiplier
      # Example: Speed 6, medium bot, with momentum = (6/1.5)² × 1.0 × 1.0 = 16 energy
      THRUST_MULTIPLIER = 1.5

      # Speed below which a rubot is considered stationary for physics calculations
      STATIONARY_SPEED_THRESHOLD = 0.1

      # Direction multiplier range for thrust cost
      # Thrusting with momentum = 1.0x, against momentum = 2.0x
      MIN_DIRECTION_MULTIPLIER = 1.0
      MAX_DIRECTION_MULTIPLIER = 2.0

      # No MAX_SPEED cap - friction and wall collisions naturally limit velocity
    end

    module Combat
      # Fire damage = energy × FIRE_DAMAGE_MULTIPLIER
      # Example: fire(10) = 10 × 1.5 = 15 damage
      FIRE_DAMAGE_MULTIPLIER = 1.5

      # Turret rotation cost = ceil(|degrees| / TURRET_TURN_DIVISOR)
      # Example: rotate_turret(90) = ceil(90/24) = 4 energy
      # Why 24: Makes continuous scanning cheap (7°/chronon = 1 energy), but snap-turns
      # costly (90° = 4 energy, 360° = 15 energy). Medium bot can sustain 240°/chronon.
      TURRET_TURN_DIVISOR = 24.0

      # Why 18: At typical 200-unit engagement, bullet arrives in ~11 chronons.
      # To dodge, bot needs ~2.1 units/chronon perpendicular velocity.
      # Moving targets (speed 5+) can dodge; stationary targets get hit.
      BULLET_SPEED = 18                  # Units per chronon
      BULLET_RADIUS = 3                  # Collision radius in units
    end

    module Rubot
      # Shield decays by this percentage each chronon: shield × (1 - DECAY_RATE)
      # 12% decay means shields halve roughly every 5-6 chronons
      SHIELD_DECAY_RATE = 0.12

      MAX_ENERGY = 100 # Energy cap for all rubot sizes

      # Size definitions: radius affects collision/targeting, energy_regen is per-chronon
      # Mass is derived: (radius / 20)² where 20 is medium radius
      # Tradeoffs:
      #   Small:  Hard to hit, cheap thrust, but fragile (80 HP)
      #   Medium: Balanced baseline
      #   Large:  Tanky (120 HP), high regen, but expensive thrust and easy target
      SIZES = {
        small: { radius: 16, energy_regen: 8, max_health: 80 },
        medium: { radius: 20, energy_regen: 10, max_health: 100 },
        large: { radius: 24, energy_regen: 12, max_health: 120 }
      }.freeze
    end

    module Energon
      RADIUS = 8                         # Collection radius in units (touch to collect)
      INITIAL_VALUE = 1                  # Starting energy value when spawned
      GROWTH_RATE = 1.0                  # Energy gained per chronon while uncollected
    end

    module Spawn
      MAX_ATTEMPTS = 100                 # Random position attempts before SpawnError

      # Energon spawn optimization: samples grid to find position maximizing distance from rubots
      ENERGON_GRID_STEP = 20             # Sample every 20 units (1024 points on 640×640)
      ENERGON_POSITION_TOLERANCE = 20    # Positions within 20 units of "best" pooled for random selection
    end

    module Movement
      # Thresholds for movement state detection (used by utility methods)
      STATIONARY_THRESHOLD = 0.5         # Speed below this == stationary for gameplay
      VELOCITY_ANGLE_THRESHOLD = 0.1     # Speed below this has no meaningful direction

      # Default parameters for Rubot utility methods
      DEFAULT_WALL_BUFFER = 50           # near_wall? default buffer
      DEFAULT_APPROACH_BUFFER = 60       # approaching_wall? default buffer
      DEFAULT_ARENA_MARGIN = 20          # clamp_to_arena default margin
      DEFAULT_ALIGNMENT_TOLERANCE = 45   # momentum_aligned? tolerance in degrees
    end

    module Battle
      # Match length limit to prevent infinite stalemates
      DEFAULT_CHRONON_LIMIT = 10_000 # Enough for multiple engagements

      # Penalties for rubot code errors
      ERROR_DAMAGE = 20                  # Damage for exceptions in act() or callbacks

      # Concurrent execution: max time to wait for all rubots to complete act()
      # Rubots that don't respond in time simply skip their actions (no penalty)
      CHRONON_DEADLINE = 0.5             # Seconds to wait for all act() calls (lenient)
    end

    module Sensing
      # Valid probe attributes (defines what info can be requested)
      PROBE_ATTRIBUTES = %i[size position velocity turret_angle shield health energy].freeze

      # Probe costs: base + sum of requested attribute costs
      # Cheap attributes reveal less tactical info, expensive ones reveal more
      PROBE_BASE_COST = 0
      PROBE_ATTRIBUTE_COSTS = {
        size: 1,                         # Just detection + size category
        position: 4,                     # Exact coordinates (most valuable for aiming)
        velocity: 3,                     # Movement prediction
        turret_angle: 2,                 # Where they're aiming
        shield: 2,                       # Defensive state
        health: 3,                       # Kill priority targeting
        energy: 3                        # Offensive capability assessment
      }.freeze

      # Scan cost: BASE + ceil(angle/ANGLE_DIVISOR) + ceil(distance/DISTANCE_DIVISOR)
      # Example: scan(angle: 60, distance: 200) = 3 + 3 + 2 = 8 energy
      SCAN_BASE_COST = 3
      SCAN_ANGLE_DIVISOR = 20.0          # Degrees per energy unit
      SCAN_DISTANCE_DIVISOR = 100.0      # Units per energy unit
      SCAN_VELOCITY_COST = 2             # Extra cost to include velocity data
      SCAN_OWNER_COST = 1                # Extra cost to include bullet owner info

      # Pulse cost: BASE + ceil(distance/DISTANCE_DIVISOR)
      # Cheaper than scan but no velocity data and 360° only
      PULSE_BASE_COST = 2
      PULSE_DISTANCE_DIVISOR = 75.0      # Units per energy unit (cheaper range than scan)
      PULSE_OWNER_COST = 1               # Extra cost to include bullet owner info

      # Detect: counter-intelligence (who sensed you this chronon)
      DETECT_COST = 2

      # Minimum distance for meaningful angle calculations (avoids division by zero)
      MIN_MEASURABLE_DISTANCE = Float::EPSILON
    end

    module Targeting
      # Defaults for SimpleTargeting utility module (can be overridden per-rubot)
      BULLET_SPEED = Combat::BULLET_SPEED  # Reference for lead calculations
      MAX_LEAD_CHRONONS = 15               # Cap on prediction distance (prevents over-leading)
      ALIGNMENT_TOLERANCE = 15             # Degrees: turret "close enough" to fire
      MAX_TURRET_TURN = 20                 # Max rotation per chronon in SimpleTargeting
      TARGET_TIMEOUT = 30                  # Chronons before tracked target considered stale
    end
  end
end
