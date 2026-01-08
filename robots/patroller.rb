# frozen_string_literal: true

# A small wall-hugging kiter that patrols the arena perimeter.
# Stays on walls to limit scan area (only looks inward).
# Kites along wall: retreats when enemies close, advances when far.
class Patroller
  include Rubowar::Rubot

  size :small

  OPTIMAL_RANGE = 200    # Sweet spot for shooting
  TOO_CLOSE = 120        # Back off along wall
  TOO_FAR = 300          # Move closer along wall
  WALL_DIST = 50         # Target distance from wall
  SCAN_INWARD = 60       # Scan angle toward center

  def on_spawn
    @target = nil
    @direction = 1       # 1 = clockwise, -1 = counter-clockwise
    @evading = 0
  end

  def tick
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
    # We want to be on the wall - just reverse if stuck
    @direction *= -1 if rand < 0.3
  end

  private

  def check_threats
    detect if tick_number % 3 == 0
    return unless detect_result

    # Evade if being probed
    if (detect_result[:probed] || 0).positive?
      @evading = 10
      @direction *= -1
    end
  end

  def scan_inward
    # Only scan every other tick, and only toward arena center
    return unless tick_number.odd? && energy > 12

    scan(angle: SCAN_INWARD, distance: 350)
    return unless scan_result

    rubots = scan_result.select { |t| t[:type] == :rubot }
    @target = rubots.min_by { |t| distance_to(t[:x], t[:y]) } if rubots.any?
  end

  def kite_along_wall
    # Priority: brake if about to hit wall
    if wall_emergency?
      brake_from_wall
    elsif @evading.positive?
      @evading -= 1
      evade_along_wall
    elsif @target
      kite_target
    else
      patrol_wall
    end
  end

  def wall_emergency?
    # Emergency if close with any momentum toward wall
    (x < WALL_DIST && velocity_x.negative?) ||
      (x > arena_width - WALL_DIST && velocity_x.positive?) ||
      (y < WALL_DIST && velocity_y.negative?) ||
      (y > arena_height - WALL_DIST && velocity_y.positive?)
  end

  def brake_from_wall
    # Thrust toward center to kill momentum
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    thrust(speed: 3, angle: center_angle)
  end

  def evade_along_wall
    # Run along wall in current direction (lower speed for inertia)
    thrust(speed: 4, angle: adjusted_wall_angle)
  end

  def kite_target
    dist = distance_to(@target[:x], @target[:y])

    # Determine whether to flee, advance, or hold along wall
    if dist < TOO_CLOSE
      # Too close - run away along wall
      @direction = away_direction
      thrust(speed: 3, angle: adjusted_wall_angle)
    elsif dist > TOO_FAR
      # Too far - move closer along wall
      @direction = toward_direction
      thrust(speed: 3, angle: adjusted_wall_angle)
    else
      # Optimal range - strafe along wall
      thrust(speed: 2, angle: adjusted_wall_angle)
    end
  end

  def patrol_wall
    # Move along nearest wall toward center-ish
    thrust(speed: 2, angle: adjusted_wall_angle)
    # Point turret inward
    turret_toward_center
  end

  # Adjust movement angle to maintain wall distance
  def adjusted_wall_angle
    base = wall_parallel_angle
    wall_d = wall_distance

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

  def wall_distance
    [x, y, arena_width - x, arena_height - y].min
  end

  def aim_and_fire
    if @target
      # Aim with lead prediction if we have velocity
      target_x = @target[:x]
      target_y = @target[:y]

      if @target[:velocity_x] && @target[:velocity_y]
        dist = distance_to(target_x, target_y)
        bullet_speed = Rubowar::Config::Combat::BULLET_SPEED
        lead = dist / bullet_speed
        target_x += @target[:velocity_x] * lead
        target_y += @target[:velocity_y] * lead
      end

      target_angle = angle_to(target_x, target_y)
      diff = normalize_angle(target_angle - turret_angle)
      turret(diff.clamp(-15, 15))

      # Fire when aligned
      if diff.abs < 18 && energy > 18
        fire(15)
      end
    else
      turret_toward_center
    end
  end

  def turret_toward_center
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    diff = normalize_angle(center_angle - turret_angle)
    turret(diff.clamp(-8, 8))
  end

  # Returns angle to move parallel to nearest wall
  def wall_parallel_angle
    case nearest_wall
    when :bottom then @direction.positive? ? 0 : 180    # Move left/right
    when :top then @direction.positive? ? 180 : 0
    when :left then @direction.positive? ? 90 : 270    # Move up/down
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
      (target_angle > 90 && target_angle < 270) ? 1 : -1
    end
  end

  # Which direction along wall moves toward target?
  def toward_direction
    -away_direction
  end

  def nearest_wall
    distances = {
      bottom: y,
      top: arena_height - y,
      left: x,
      right: arena_width - x
    }
    distances.min_by { |_, d| d }.first
  end
end
