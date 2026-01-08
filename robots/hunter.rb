# frozen_string_literal: true

# A rubot that patrols the arena looking for targets, then chases them down.
# Uses pulse for wide-area detection and scan for precision targeting.
# Small size for better mobility and survivability.
#
# Inertia-aware: Uses momentum helpers to avoid walls and efficiently pursue.
class Hunter
  include Rubowar::Rubot

  size :small # Small = faster acceleration, harder to hit, cheaper movement

  WALL_BUFFER = 80
  PULSE_DISTANCE = 300
  SCAN_ANGLE = 70
  SCAN_ANGLE_WIDE = 100
  SCAN_DISTANCE = 350
  PATROL_THRUST = 3       # Lower thrust for efficient patrol
  CHASE_THRUST = 4        # Moderate thrust for pursuit
  BRAKE_THRUST = 3        # Thrust for braking/direction changes
  BULLET_SPEED = Rubowar::Config::Combat::BULLET_SPEED
  GIVE_UP_CHRONONS = 50
  ENERGON_COLLECT_RANGE = 250

  def on_spawn
    @mode = :patrol
    @target = nil # Combined target data
    @patrol_angle = rand(360)
    @chronons_without_target = 0
    @pulse_cooldown = 0
    @dodge_direction = 1
    @probe_cooldown = 0
    @target_energon = nil
  end

  def act
    # Priority 1: Don't hit walls
    if approaching_wall?(WALL_BUFFER)
      brake_from_wall
      return
    end

    case @mode
    when :patrol
      patrol_action
    when :chase
      chase_action
    when :collecting
      collecting_action
    end
  end

  def on_hit(_damage, direction)
    @dodge_direction *= -1
    # Brake first if moving fast, then dodge
    if speed > 3
      # Thrust against current velocity to slow down
      brake_thrust
    else
      # Dodge perpendicular to incoming fire
      dodge_angle = direction + (90 * @dodge_direction)
      thrust(speed: BRAKE_THRUST, angle: dodge_angle)
    end

    shield(6) if energy > 25 && shield_level < 40

    return unless @mode == :patrol

    # Estimate attacker position
    attacker_angle = (direction + 180) % 360
    estimated_dist = 200
    @target = {
      x: x + (Math.cos(attacker_angle * Math::PI / 180) * estimated_dist),
      y: y + (Math.sin(attacker_angle * Math::PI / 180) * estimated_dist),
      velocity_x: nil,
      velocity_y: nil
    }
    @mode = :chase
    @chronons_without_target = 0
  end

  def on_wall
    # Bounce recovery - reverse patrol direction
    @patrol_angle = (velocity_angle || @patrol_angle) + 180 + rand(-30..30)
    @patrol_angle %= 360
  end

  def on_energon(_amount)
    @target_energon = nil
    @mode = :patrol
  end

  private

  def brake_from_wall
    # Thrust toward center to kill momentum
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    thrust(speed: BRAKE_THRUST, angle: center_angle)
    turret(5) # Keep scanning while braking
  end

  def brake_thrust
    # Thrust opposite to current velocity
    return unless velocity_angle

    brake_angle = (velocity_angle + 180) % 360
    thrust(speed: BRAKE_THRUST, angle: brake_angle)
  end

  def patrol_action
    # SENSE: Pulse periodically to find targets
    @pulse_cooldown -= 1 if @pulse_cooldown.positive?
    if @pulse_cooldown <= 0
      pulse(distance: PULSE_DISTANCE)
      @pulse_cooldown = 3

      if pulse_result
        rubots = pulse_result.select { |t| t[:type] == :rubot }
        if rubots.any?
          closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
          acquire_target(closest)
          return
        end
      end
    end

    # Check for energons when no combat target
    if energy < 80
      energon = find_nearest_energon(max_distance: ENERGON_COLLECT_RANGE)
      if energon
        @target_energon = energon
        @mode = :collecting
        return collecting_action
      end
    end

    # MOVE: Patrol with inertia awareness
    adjust_patrol_for_walls
    turret(8)

    # Only thrust if we need to change direction or speed up
    patrol_angle_safe = safe_angle(@patrol_angle)
    if momentum_aligned?(patrol_angle_safe, tolerance: 60)
      # Aligned - gentle thrust to maintain/increase speed
      thrust(speed: PATROL_THRUST, angle: patrol_angle_safe) if speed < 8
    elsif speed > 5
      # Moving wrong direction at speed - brake first
      brake_thrust
    else
      # Need to change direction - thrust toward desired angle
      thrust(speed: PATROL_THRUST, angle: patrol_angle_safe)
    end

    # Light shields during patrol
    shield(3) if energy > 50 && shield_level < 20
  end

  def chase_action
    return revert_to_patrol unless @target

    # === SENSE PHASE ===
    current_scan_angle = @chronons_without_target > 5 ? SCAN_ANGLE_WIDE : SCAN_ANGLE
    scan(angle: current_scan_angle, distance: SCAN_DISTANCE, velocity: true)

    if scan_result
      rubots = scan_result.select { |t| t[:type] == :rubot }
      if rubots.any?
        closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
        update_target(closest)
        @chronons_without_target = 0
      else
        @chronons_without_target += 1
      end
    else
      @chronons_without_target += 1
    end

    # Wider pulse when losing target
    if @chronons_without_target > 10 && (@chronons_without_target % 5).zero?
      pulse(distance: PULSE_DISTANCE + 100)
      if pulse_result
        rubots = pulse_result.select { |t| t[:type] == :rubot }
        if rubots.any?
          closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
          update_target(closest)
          @chronons_without_target = 5
        end
      end
    end

    return revert_to_patrol if @chronons_without_target > GIVE_UP_CHRONONS

    # Probe for detailed info when aligned
    lead_x, lead_y = calculate_lead_position
    target_angle = angle_to(lead_x, lead_y)
    turret_diff = normalize_angle(target_angle - turret_angle)

    @probe_cooldown -= 1 if @probe_cooldown.positive?
    if @probe_cooldown <= 0 && turret_diff.abs < 15 && energy > 15
      probe(:position, :velocity, :health)
      @probe_cooldown = 8
      if probe_result&.any?
        update_target(probe_result)
        @chronons_without_target = 0
      end
    end

    # === MOVE PHASE ===
    turret(turret_diff.clamp(-25, 25))

    # Inertia-aware pursuit
    pursue_target

    # === COMBAT PHASE ===
    if turret_diff.abs < 30
      dist = distance_to(@target[:x], @target[:y])
      target_weak = @target[:health] && @target[:health] < 40
      fire_power = if (dist < 80 && turret_diff.abs < 10) || target_weak
                     15
                   elsif dist < 120 && turret_diff.abs < 12
                     12
                   else
                     8
                   end
      min_energy = target_weak ? 15 : 20
      fire(fire_power) if energy > min_energy
    end

    shield(5) if energy > 35 && shield_level < 25
  end

  def pursue_target
    return unless @target

    base_x = @target[:x]
    base_y = @target[:y]
    dist = distance_to(base_x, base_y)

    # Calculate pursuit angle with intercept prediction
    pursuit_angle = calculate_pursuit_angle
    pursuit_angle = safe_angle(pursuit_angle)

    # Inertia-aware thrust decision
    if dist < 60
      # Very close - match target movement or hold position
      thrust(speed: 2, angle: pursuit_angle) if speed < 5
    elsif momentum_aligned?(pursuit_angle, tolerance: 45)
      # Good alignment - accelerate toward target
      thrust_speed = dist > 200 ? CHASE_THRUST : 3
      thrust(speed: thrust_speed, angle: pursuit_angle) if speed < 12
    elsif speed > 6
      # Need direction change - brake then redirect
      brake_thrust
    else
      thrust(speed: CHASE_THRUST, angle: pursuit_angle)
    end
  end

  def calculate_pursuit_angle
    return angle_to(@target[:x], @target[:y]) unless @target[:velocity_x] && @target[:velocity_y]

    target_speed = speed_from_velocity(@target[:velocity_x], @target[:velocity_y])
    return angle_to(@target[:x], @target[:y]) if target_speed < 1

    # Intercept calculation accounting for our acceleration time
    dist = distance_to(@target[:x], @target[:y])

    # With inertia, we can't instantly reach max speed
    # Estimate time to intercept more conservatively
    avg_chase_speed = [speed, 6].max # Assume we'll average at least 6
    time_to_intercept = dist / avg_chase_speed

    # Predict where target will be, with friction decay
    friction = 0.92
    intercept_x = @target[:x]
    intercept_y = @target[:y]
    vx = @target[:velocity_x]
    vy = @target[:velocity_y]

    # Simulate target movement with friction
    time_to_intercept.clamp(1, 20).to_i.times do
      intercept_x += vx
      intercept_y += vy
      vx *= friction
      vy *= friction
    end

    # Clamp to arena bounds
    intercept_x = intercept_x.clamp(30, arena_width - 30)
    intercept_y = intercept_y.clamp(30, arena_height - 30)

    angle_to(intercept_x, intercept_y)
  end

  def calculate_lead_position
    return [@target[:x], @target[:y]] unless @target[:velocity_x] && @target[:velocity_y]

    lead_position(
      @target[:x], @target[:y],
      @target[:velocity_x], @target[:velocity_y],
      projectile_speed: BULLET_SPEED
    )
  end

  def update_target(data)
    @target = {
      x: data[:x],
      y: data[:y],
      velocity_x: data[:velocity_x],
      velocity_y: data[:velocity_y],
      health: data[:health] || @target&.dig(:health)
    }
  end

  def acquire_target(data)
    @mode = :chase
    update_target(data)
    @chronons_without_target = 0

    # Turn turret toward target
    target_angle = angle_to(@target[:x], @target[:y])
    turret_diff = normalize_angle(target_angle - turret_angle)
    turret(turret_diff.clamp(-25, 25))
  end

  def revert_to_patrol
    @mode = :patrol
    @target = nil
    @chronons_without_target = 0
    @pulse_cooldown = 0
    @probe_cooldown = 0
  end

  def adjust_patrol_for_walls
    # Proactively adjust patrol angle to avoid walls
    return unless wall_distance(@patrol_angle) < WALL_BUFFER * 2

    # Current patrol angle leads to wall - pick a better direction
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    @patrol_angle = center_angle + rand(-45..45)
    @patrol_angle %= 360
  end

  # Adjust angle to avoid walls (returns safe angle)
  def safe_angle(angle)
    return angle if wall_distance(angle) > WALL_BUFFER * 1.5

    # Angle leads too close to wall - deflect toward center
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    # Blend toward center
    diff = normalize_angle(center_angle - angle)
    (angle + (diff * 0.5)) % 360
  end

  def collecting_action
    @pulse_cooldown -= 1 if @pulse_cooldown.positive?
    if @pulse_cooldown <= 0
      pulse(distance: PULSE_DISTANCE)
      @pulse_cooldown = 3

      if pulse_result
        rubots = pulse_result.select { |t| t[:type] == :rubot }
        if rubots.any?
          closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
          @target_energon = nil
          acquire_target(closest)
          return
        end
      end
    end

    unless energon_still_exists?(@target_energon)
      @target_energon = nil
      @mode = :patrol
      return
    end

    # Move toward energon with inertia awareness
    energon_angle = angle_to(@target_energon[:x], @target_energon[:y])
    energon_dist = distance_to(@target_energon[:x], @target_energon[:y])
    safe_energon_angle = safe_angle(energon_angle)

    collect_thrust = energon_dist < 50 ? 2 : 3
    if momentum_aligned?(safe_energon_angle, tolerance: 60)
      thrust(speed: collect_thrust, angle: safe_energon_angle) if speed < 8
    else
      thrust(speed: collect_thrust, angle: safe_energon_angle)
    end

    turret(8)
  end
end
