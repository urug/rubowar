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
# Config::Battle = "Game loop settings, tick timeout"
# Config::Sensing = "Probe, scan, pulse, detect costs"
# Config::Targeting = "SimpleTargeting defaults"

module Rubowar
  module Config
    module Arena
      DEFAULT_WIDTH = 800
      DEFAULT_HEIGHT = 600
      DEFAULT_FRICTION = 0.95

      # Spawn distance ratios (relative to arena dimensions)
      SPAWN_WALL_BUFFER_RATIO = 0.08        # 8% of smaller dimension
      SPAWN_MIN_DISTANCE_RATIO = 0.12       # 12% of diagonal
      SPAWN_MAX_DISTANCE_RATIO = 0.50       # 50% of diagonal

      # Energon spawn settings
      ENERGON_WALL_BUFFER_RATIO = 0.15      # 15% of smaller dimension
      ENERGON_SPAWN_INTERVAL = 80
    end

    module Physics
      COLLISION_BASE_DAMAGE = 2
      COLLISION_VELOCITY_MULTIPLIER = 0.5
      WALL_VELOCITY_MULTIPLIER = 0.75
      WALL_BOUNCE_COEFFICIENT = 0.12
      THRUST_MULTIPLIER = 1.5
      STATIONARY_SPEED_THRESHOLD = 0.1
      MAX_SPEED = 30
    end

    module Combat
      FIRE_DAMAGE_MULTIPLIER = 1.5
      TURRET_TURN_DIVISOR = 24.0
      BULLET_SPEED = 18
      BULLET_RADIUS = 3
    end

    module Rubot
      MAX_ENERGY = 100
      SHIELD_DECAY_RATE = 0.12

      SIZES = {
        small: { radius: 15, energy_regen: 8, max_health: 80 },
        medium: { radius: 20, energy_regen: 10, max_health: 100 },
        large: { radius: 25, energy_regen: 12, max_health: 120 }
      }.freeze
    end

    module Energon
      RADIUS = 8
      INITIAL_VALUE = 1
      GROWTH_RATE = 1.0
    end

    module Battle
      DEFAULT_TICK_LIMIT = 10_000
      ERROR_DAMAGE = 10
      TICK_TIMEOUT = 0.1          # 100ms max per tick
      TIMEOUT_DAMAGE = 50         # Severe penalty for timeouts
    end

    module Sensing
      # Probe costs
      PROBE_BASE_COST = 0
      PROBE_ATTRIBUTE_COSTS = {
        size: 1,
        position: 4,
        velocity: 3,
        turret_angle: 2,
        shield: 2,
        health: 3,
        energy: 3
      }.freeze

      # Scan costs
      SCAN_BASE_COST = 3
      SCAN_ANGLE_DIVISOR = 20.0
      SCAN_DISTANCE_DIVISOR = 100.0
      SCAN_VELOCITY_COST = 2
      SCAN_OWNER_COST = 1

      # Pulse costs
      PULSE_BASE_COST = 2
      PULSE_DISTANCE_DIVISOR = 75.0
      PULSE_OWNER_COST = 1

      # Detect cost (counter-intelligence)
      DETECT_COST = 2
    end

    module Targeting
      BULLET_SPEED = 18
      MAX_LEAD_TICKS = 15
      ALIGNMENT_TOLERANCE = 15    # degrees
      MAX_TURRET_TURN = 20        # degrees per tick
      TARGET_TIMEOUT = 30         # ticks before target goes stale
    end
  end
end
