# frozen_string_literal: true

# [file]
# purpose = "Pure physics calculations for the Rubowar battle arena"
# responsibility = "Collision damage, bounce velocities, mass calculations, separation directions"
# pattern = "Module Functions (stateless calculations)"
#
# [module.Physics]
# purpose = "Provides pure physics calculations as module functions"
# usage = "Physics.mass_factor(radius), Physics.collision_damage(...), etc."
# note = "All methods are stateless and take primitive values as input"
#
# [key_methods]
# collision = ["collision_damage", "collision_bounce", "collision_separation", "separation_direction"]
# walls = ["wall_damage", "wall_bounce"]
# thrust = ["thrust_direction_multiplier", "thrust_cost", "thrust_speed_from_energy", "thrust_velocity"]
# utilities = ["mass_factor", "distance"]

module Rubowar
  module Physics
    # Memoized mass factors by radius to avoid repeated calculations.
    # Thread-safe: Hash#[] is atomic in CRuby, and values are computed once per radius.
    @mass_factors = {}

    module_function

    # Calculate mass factor based on radius (relative to medium bot size).
    # Memoized since this is called frequently and the result is constant per radius.
    def mass_factor(radius)
      @mass_factors[radius] ||= begin
        medium_radius = Config::Rubot::SIZES[:medium][:radius].to_f
        (radius / medium_radius)**2
      end
    end

    # Euclidean distance between two points
    def distance(x1:, y1:, x2:, y2:)
      Math.sqrt(((x1 - x2)**2) + ((y1 - y2)**2))
    end

    # Normalize angle to -180..180 range (180 is preferred over -180)
    def normalize_angle(angle)
      result = ((angle + 180) % 360) - 180
      result == -180 ? 180 : result
    end

    # Calculate damage from collision based on relative velocity
    def collision_damage(rel_vx:, rel_vy:, mass:)
      closing_speed = Math.sqrt((rel_vx**2) + (rel_vy**2))
      momentum_damage = mass * closing_speed * Config::Physics::COLLISION_VELOCITY_MULTIPLIER
      (Config::Physics::COLLISION_BASE_DAMAGE + momentum_damage).round
    end

    # Calculate damage from wall impact
    def wall_damage(vx:, vy:, normal_x:, normal_y:, mass:)
      impact_speed = -((vx * normal_x) + (vy * normal_y))
      return 0 if impact_speed <= 0

      momentum_damage = mass * impact_speed * Config::Physics::COLLISION_VELOCITY_MULTIPLIER
      (Config::Physics::COLLISION_BASE_DAMAGE + momentum_damage).round
    end

    # Calculate new velocities after wall bounce
    # Returns { vx:, vy: } or nil if not moving into wall
    def wall_bounce(vx:, vy:, normal_x:, normal_y:, bot_mass:)
      velocity_into_wall = (vx * normal_x) + (vy * normal_y)

      # Only bounce if moving into wall
      return nil if velocity_into_wall >= 0

      elasticity = Config::Physics::WALL_ELASTICITY
      wall_mass = Config::Physics::WALL_MASS

      impulse = -(1 + elasticity) * velocity_into_wall / ((1 / bot_mass) + (1 / wall_mass))

      {
        vx: vx + ((impulse / bot_mass) * normal_x),
        vy: vy + ((impulse / bot_mass) * normal_y)
      }
    end

    # Calculate velocity adjustments for bot-bot collision bounce
    # Returns { a_vx:, a_vy:, b_vx:, b_vy: } - deltas to add to velocities
    def collision_bounce(a_vx:, a_vy:, b_vx:, b_vy:, nx:, ny:, mass_a:, mass_b:)
      # Relative velocity of A with respect to B
      dvx = a_vx - b_vx
      dvy = a_vy - b_vy

      # Relative velocity along collision normal
      dvn = (dvx * nx) + (dvy * ny)

      # Don't bounce if already separating
      return { a_vx: 0.0, a_vy: 0.0, b_vx: 0.0, b_vy: 0.0 } if dvn.negative?

      elasticity = Config::Physics::COLLISION_ELASTICITY

      # Impulse scalar (conservation of momentum with elasticity)
      impulse = -(1 + elasticity) * dvn / ((1 / mass_a) + (1 / mass_b))

      {
        a_vx: (impulse / mass_a) * nx,
        a_vy: (impulse / mass_a) * ny,
        b_vx: -(impulse / mass_b) * nx,
        b_vy: -(impulse / mass_b) * ny
      }
    end

    # Calculate position separation for overlapping bots
    # Returns { a_x:, a_y:, b_x:, b_y: } - deltas to add to positions
    # When distance is zero, uses velocity vectors to determine separation direction
    def collision_separation(a_x:, a_y:, b_x:, b_y:, distance:, overlap:,
                             a_vx: 0.0, a_vy: 0.0, b_vx: 0.0, b_vy: 0.0)
      dx, dy = separation_direction(
        a_x:, a_y:, b_x:, b_y:, distance:,
        a_vx:, a_vy:, b_vx:, b_vy:
      )

      {
        a_x: dx * overlap / 2,
        a_y: dy * overlap / 2,
        b_x: -dx * overlap / 2,
        b_y: -dy * overlap / 2
      }
    end

    # Determine separation direction unit vector
    # Falls back to velocity-based or arbitrary direction if positions coincide
    def separation_direction(a_x:, a_y:, b_x:, b_y:, distance:, a_vx:, a_vy:, b_vx:, b_vy:)
      # Normal case: use position difference
      return [(a_x - b_x) / distance, (a_y - b_y) / distance] if distance > Config::Sensing::MIN_MEASURABLE_DISTANCE

      # Zero distance: try using relative velocity to separate
      rel_vx = a_vx - b_vx
      rel_vy = a_vy - b_vy
      rel_speed = Math.sqrt((rel_vx**2) + (rel_vy**2))

      return [rel_vx / rel_speed, rel_vy / rel_speed] if rel_speed > Config::Sensing::MIN_MEASURABLE_DISTANCE

      # Edge case: both stationary at exact same position (extremely rare - requires
      # pixel-perfect spawn overlap). Use deterministic X-axis separation to ensure
      # consistent behavior. This is acceptable since spawn positioning prevents this
      # in practice, and collision separation will push them apart after one chronon.
      [1.0, 0.0]
    end

    # Calculate thrust energy cost multiplier based on direction change
    # Thrusting against current momentum costs more
    def thrust_direction_multiplier(vx:, vy:, thrust_angle:, speed:)
      return 1.0 if speed < Config::Physics::STATIONARY_SPEED_THRESHOLD

      current_angle = Math.atan2(vy, vx) * 180 / Math::PI
      angle_diff = normalize_angle(thrust_angle - current_angle).abs

      # 0° diff = 1.0x, 90° diff = 1.5x, 180° diff = 2.0x
      1.0 + (angle_diff / 180.0)
    end

    # Calculate thrust energy cost
    def thrust_cost(speed:, mass:, direction_multiplier:)
      base_cost = (speed / Config::Physics::THRUST_MULTIPLIER)**2
      (base_cost * mass * direction_multiplier).ceil
    end

    # Calculate actual speed from available energy (for partial thrust)
    def thrust_speed_from_energy(energy:, mass:, direction_multiplier:)
      effective_energy = energy / (mass * direction_multiplier)
      Math.sqrt(effective_energy) * Config::Physics::THRUST_MULTIPLIER
    end

    # Calculate velocity change from thrust
    # Returns { vx:, vy: } - deltas to add to velocity
    def thrust_velocity(speed:, angle:, mass:)
      radians = angle * Math::PI / 180
      acceleration = speed / mass
      { vx: Math.cos(radians) * acceleration, vy: Math.sin(radians) * acceleration }
    end
  end
end
