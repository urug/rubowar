# frozen_string_literal: true

# A small wall-hugging kiter that patrols the arena perimeter.
# Stays near walls to limit scan area (only looks inward).
# Kites along wall: retreats when enemies close, advances when far.
#
# Momentum-aware: Uses inertia helpers for smooth wall patrol.
class Patroller
  include Rubowar::Rubot

  size :small

  OPTIMAL_RANGE = 200    # Sweet spot for shooting
  TOO_CLOSE = 120        # Back off along wall
  TOO_FAR = 300          # Move closer along wall
  WALL_DIST = 50         # Target distance from wall
  SCAN_INWARD = 60       # Scan angle toward center
  WALL_BUFFER = 60       # Emergency brake distance
  PATROL_THRUST = 3      # Normal patrol speed
  EVADE_THRUST = 4       # Evading speed

  def on_spawn
    @target = nil
    @direction = 1       # 1 = clockwise, -1 = counter-clockwise
    @evading = 0
  end

  def act
    # Priority 1: Don't crash into walls
    if approaching_wall?(WALL_BUFFER)
      brake_from_wall
      return
    end

    check_threats
    scan_inward
    kite_along_wall
    aim_and_fire
  end

  def on_hit(_damage, _direction)
    @evading = 12
    @direction *= -1
    shield(5) if energy > 30
  end

  def on_wall
    # Hit a wall - reverse direction and brake
    @direction *= -1
    @evading = 5
  end

  private

  def check_threats
    detect if (chronons % 3).zero?
    return unless detect_result

    # Evade if being probed
    return unless (detect_result[:probed] || 0).positive?

    @evading = 10
    @direction *= -1
  end

  def scan_inward
    # Only scan every other chronon, and only toward arena center
    return unless chronons.odd? && energy > 12

    scan(angle: SCAN_INWARD, distance: 350, velocity: true)
    return unless scan_result

    rubots = scan_result.select { |t| t[:type] == :rubot }
    @target = rubots.min_by { |t| distance_to(t[:x], t[:y]) } if rubots.any?
  end

  def kite_along_wall
    if @evading.positive?
      @evading -= 1
      evade_along_wall
    elsif @target
      kite_target
    else
      patrol_wall
    end
  end

  def brake_from_wall
    # Thrust toward center to kill momentum
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    thrust(speed: PATROL_THRUST, angle: center_angle)
  end

  def evade_along_wall
    move_angle = adjusted_wall_angle
    # If already moving this way, less thrust needed
    if momentum_aligned?(move_angle, tolerance: 45)
      thrust(speed: EVADE_THRUST, angle: move_angle) if speed < 10
    elsif speed > 5
      # Moving wrong way - brake first
      brake_thrust
    else
      thrust(speed: EVADE_THRUST, angle: move_angle)
    end
  end

  def kite_target
    dist = distance_to(@target[:x], @target[:y])
    move_angle = adjusted_wall_angle

    # Determine whether to flee, advance, or hold along wall
    if dist < TOO_CLOSE
      # Too close - run away along wall
      @direction = away_direction
      move_angle = adjusted_wall_angle
      move_along_wall(move_angle, PATROL_THRUST)
    elsif dist > TOO_FAR
      # Too far - move closer along wall
      @direction = toward_direction
      move_angle = adjusted_wall_angle
      move_along_wall(move_angle, PATROL_THRUST)
    else
      # Optimal range - gentle strafe along wall
      move_along_wall(move_angle, 2)
    end
  end

  def patrol_wall
    move_angle = adjusted_wall_angle
    move_along_wall(move_angle, 2)
    turret_toward_center
  end

  def move_along_wall(move_angle, thrust_speed)
    # Momentum-aware movement along wall
    if momentum_aligned?(move_angle, tolerance: 50)
      # Already moving roughly right direction
      thrust(speed: thrust_speed, angle: move_angle) if speed < 8
    elsif speed > 4
      # Need to change direction - brake first
      brake_thrust
    else
      thrust(speed: thrust_speed, angle: move_angle)
    end
  end

  def brake_thrust
    return unless velocity_angle

    brake_angle = (velocity_angle + 180) % 360
    thrust(speed: PATROL_THRUST, angle: brake_angle)
  end

  # Adjust movement angle to maintain wall distance
  def adjusted_wall_angle
    base = wall_parallel_angle
    wall_d = current_wall_distance

    # If too close to wall, angle slightly away
    if wall_d < WALL_DIST * 0.5
      base + (inward_adjustment * 30)
    # If drifting away from wall, angle slightly toward
    elsif wall_d > WALL_DIST * 1.5
      base - (inward_adjustment * 20)
    else
      base
    end
  end

  # Returns +1 or -1 to indicate which direction is "inward" (away from wall)
  def inward_adjustment
    case nearest_wall
    when :bottom then 1   # Positive Y is inward
    when :top then -1
    when :left then 1     # Positive X is inward (angle 0)
    when :right then -1
    end
  end

  def current_wall_distance
    [x, y, arena_width - x, arena_height - y].min
  end

  def aim_and_fire
    if @target
      # Aim with lead prediction if we have velocity
      lead_x, lead_y = calculate_lead_position

      target_angle = angle_to(lead_x, lead_y)
      diff = normalize_angle(target_angle - turret_angle)
      turret(diff.clamp(-15, 15))

      # Fire when aligned
      dist = distance_to(@target[:x], @target[:y])
      if diff.abs < 18 && energy > 18 && dist < 350
        fire_power = dist < 150 ? 15 : 10
        fire(fire_power)
      end
    else
      turret_toward_center
    end

    # Light shields when not evading
    shield(3) if energy > 40 && shield_level < 20 && @evading.zero?
  end

  def calculate_lead_position
    return [@target[:x], @target[:y]] unless @target[:velocity_x] && @target[:velocity_y]

    lead_position(
      @target[:x], @target[:y],
      @target[:velocity_x], @target[:velocity_y],
      projectile_speed: Rubowar::Config::Combat::BULLET_SPEED
    )
  end

  def turret_toward_center
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    diff = normalize_angle(center_angle - turret_angle)
    turret(diff.clamp(-8, 8))
  end

  # Returns angle to move parallel to nearest wall
  def wall_parallel_angle
    case nearest_wall
    when :bottom then @direction.positive? ? 0 : 180 # Move left/right
    when :top then @direction.positive? ? 180 : 0
    when :left then @direction.positive? ? 90 : 270 # Move up/down
    when :right then @direction.positive? ? 270 : 90
    end
  end

  # Which direction along wall moves away from target?
  def away_direction
    return @direction unless @target

    target_angle = angle_to(@target[:x], @target[:y])
    wall = nearest_wall

    case wall
    when :bottom, :top
      # On horizontal wall - check if target is to our left or right
      target_angle < 180 ? -1 : 1
    when :left, :right
      # On vertical wall - check if target is above or below
      target_angle > 90 && target_angle < 270 ? 1 : -1
    end
  end

  # Which direction along wall moves toward target?
  def toward_direction
    -away_direction
  end
end
