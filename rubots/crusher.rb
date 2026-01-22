# frozen_string_literal: true

# A wall-ramming specialist designed to counter corner campers.
#
# Core strategy: Always approach from the angle that rams targets INTO walls.
# Wall collisions deal extra damage and trap targets for follow-up rams.
#
# Anti-corner-camping tactics:
# - Approach from opposite side of nearest wall (push them into it)
# - Corner targets take damage from TWO walls - prioritize them
# - Keep ramming pinned targets repeatedly
# - Fire while closing and while crushing
class Crusher
  include Rubowar::Rubot

  size :large # Mass 1.44 = devastating rams, 120 HP to tank return fire

  WALL_DANGER = 100       # Target this close to wall = attack opportunity
  CORNER_ZONE = 120       # Corner detection radius
  ENGAGE_DISTANCE = 250   # Start pursuing at this range
  RAM_COMMIT = 80         # Fully commit to ram
  CRUSH_RANGE = 50        # Stay this close when crushing
  PIN_THRESHOLD = 35      # Target is "pinned" if this close to wall

  def on_spawn
    @mode = :hunting
    @target = nil
    @crush_start = nil
    @last_pulse = -100
  end

  def act
    sense_targets
    track_target

    case @mode
    when :hunting
      hunt
    when :positioning
      position_for_ram
    when :ramming
      execute_ram
    when :crushing
      crush_pinned_target
    end
  end

  def on_collision(other:)
    # Successful ram - if they're pinned, start crushing
    return unless @target && target_pinned?

    @mode = :crushing
    @crush_start = chronon
  end

  def on_hit(damage:, direction:)
    # Someone's shooting us - find them and ram them
    return if @target && @mode == :crushing

    attacker_angle = (direction + 180) % 360
    @target = {
      x: x + (Math.cos(attacker_angle * Math::PI / 180) * 150),
      y: y + (Math.sin(attacker_angle * Math::PI / 180) * 150)
    }
    @mode = :positioning
  end

  def on_wall
    # We hit a wall - recalculate approach
    @mode = :positioning if @mode == :ramming
  end

  private

  def sense_targets
    # Pulse every few ticks for awareness
    if chronon - @last_pulse >= 8
      pulse(distance: 400)
      @last_pulse = chronon

      if pulse_echo.any_rubots?
        # Prioritize: corner-trapped > wall-adjacent > closest
        best = pulse_echo.rubots.min_by do |t|
          dist = distance_to(target_x: t.x, target_y: t.y)
          target_hash = { x: t.x, y: t.y }
          wall_dist = wall_distance_of(target_hash)

          corner_bonus = in_corner?(target_hash) ? -300 : 0
          wall_bonus = wall_dist < WALL_DANGER ? -150 : 0

          dist + corner_bonus + wall_bonus
        end

        @target = { x: best.x, y: best.y } if best
        @mode = :positioning if @target && @mode == :hunting
      end
    end

    # Use scan to get velocity data for better tracking
    update_target_from_scan if @target && energy > 15
  end

  def update_target_from_scan
    # Scan in direction of target to get velocity
    scan(angle: 60, distance: 350, velocity: true)
    return unless scan_echo.any_rubots?

    closest = scan_echo.closest_rubot(to_x: x, to_y: y)
    @target = {
      x: closest.x,
      y: closest.y,
      velocity_x: closest.velocity_x,
      velocity_y: closest.velocity_y
    }
  end

  def track_target
    return unless @target

    # Calculate lead angle if we have velocity data
    target_angle = if @target[:velocity_x] && @target[:velocity_y]
                     lead_angle(
                       target_x: @target[:x],
                       target_y: @target[:y],
                       velocity_x: @target[:velocity_x],
                       velocity_y: @target[:velocity_y],
                       projectile_speed: Rubowar::Config::Combat::BULLET_SPEED
                     )
                   else
                     angle_to(target_x: @target[:x], target_y: @target[:y])
                   end

    turret_diff = normalize_angle(target_angle - turret_angle)

    # Rotate faster when far off target, slower when close for precision
    max_rotation = turret_diff.abs > 45 ? 20 : 15
    rotate_turret(turret_diff.clamp(-max_rotation, max_rotation))
  end

  def hunt
    # No target - patrol toward center, scan around
    center_angle = angle_to(target_x: arena_width / 2, target_y: arena_height / 2)

    thrust(speed: 4, angle: center_angle) if (distance_to(target_x: arena_width / 2, target_y: arena_height / 2) > 150) && (speed < 8)

    rotate_turret(15)
    raise_shields(5) if energy > 60 && shield_level < 30
  end

  def position_for_ram
    return hunt unless @target

    dist = distance_to(target_x: @target[:x], target_y: @target[:y])

    # If close enough to ram, do it
    if dist < RAM_COMMIT
      @mode = :ramming
      return
    end

    # Calculate ram angle: approach from opposite side of their nearest wall
    ram_angle = calculate_ram_angle

    # Move to attack position
    if dist > ENGAGE_DISTANCE
      # Far away - close distance directly first
      approach_angle = angle_to(target_x: @target[:x], target_y: @target[:y])
      thrust(speed: 5, angle: approach_angle) if speed < 12
    elsif speed < 14
      # In range - position for wall ram
      thrust(speed: 6, angle: ram_angle)
    end

    # Fire while closing
    aim_and_fire
    # Moderate shields - save energy for thrust
    raise_shields(8) if energy > 50 && shield_level < 60
  end

  def execute_ram
    return hunt unless @target

    # Check if target is now pinned
    if target_pinned?
      @mode = :crushing
      @crush_start = chronon
      return
    end

    # Ram angle pushes them into wall
    ram_angle = calculate_ram_angle

    # Full speed ram
    if momentum_aligned?(ram_angle, tolerance: 40)
      thrust(speed: 8, angle: ram_angle) if speed < 18
    else
      # Adjust trajectory
      thrust(speed: 6, angle: ram_angle)
    end

    # Fire while ramming
    aim_and_fire
    # Heavy shields for impact
    raise_shields(12) if energy > 40 && shield_level < 80
  end

  def crush_pinned_target
    return hunt unless @target

    dist = distance_to(target_x: @target[:x], target_y: @target[:y])

    # Stop crushing if: target escaped, timeout, or target dead (no update)
    if !target_pinned? || (chronon - @crush_start) > 60
      @mode = :positioning
      @crush_start = nil
      return
    end

    # Ram them into the wall repeatedly
    if dist > CRUSH_RANGE
      # Close in for another ram
      ram_angle = angle_to(target_x: @target[:x], target_y: @target[:y])
      thrust(speed: 6, angle: ram_angle) if speed < 12
    elsif dist < 25
      # Too close, back up slightly for momentum
      backup_angle = (angle_to(target_x: @target[:x], target_y: @target[:y]) + 180) % 360
      thrust(speed: 3, angle: backup_angle)
    else
      # Perfect range - ram into wall
      ram_angle = calculate_ram_angle
      thrust(speed: 7, angle: ram_angle) if speed < 15
    end

    # Fire at pinned target - easy hits
    aim_and_fire(aggressive: true)
    raise_shields(6) if energy > 35 && shield_level < 50
  end

  # Calculate angle that pushes target INTO their nearest wall
  # We need to hit them from the opposite side of their nearest wall
  def calculate_ram_angle
    return angle_to(target_x: @target[:x], target_y: @target[:y]) unless @target

    nearest = nearest_wall_to(@target)

    # Calculate ideal attack position (opposite side of wall from target)
    case nearest
    when :left
      # Target near left wall - we want to be EAST of them, pushing west
      ideal_x = @target[:x] + 100
      ideal_y = @target[:y]
    when :right
      # Target near right wall - we want to be WEST of them, pushing east
      ideal_x = @target[:x] - 100
      ideal_y = @target[:y]
    when :top
      # Target near top wall - we want to be SOUTH of them, pushing north
      ideal_x = @target[:x]
      ideal_y = @target[:y] - 100
    when :bottom
      # Target near bottom wall - we want to be NORTH of them, pushing south
      ideal_x = @target[:x]
      ideal_y = @target[:y] + 100
    end

    # If we're already roughly in position, ram directly at target
    # Otherwise, move toward the ideal attack position
    dist_to_ideal = distance_to(target_x: ideal_x, target_y: ideal_y)
    dist_to_target = distance_to(target_x: @target[:x], target_y: @target[:y])

    if dist_to_ideal < 60 || dist_to_target < RAM_COMMIT
      # In position or close enough - ram directly
      angle_to(target_x: @target[:x], target_y: @target[:y])
    else
      # Move toward attack position
      angle_to(target_x: ideal_x.clamp(50, arena_width - 50), target_y: ideal_y.clamp(50, arena_height - 50))
    end
  end

  def nearest_wall_to(target)
    distances = {
      left: target[:x],
      right: arena_width - target[:x],
      top: arena_height - target[:y],
      bottom: target[:y]
    }
    distances.min_by { |_, d| d }.first
  end

  def wall_distance_of(target)
    [
      target[:x],
      arena_width - target[:x],
      target[:y],
      arena_height - target[:y]
    ].min
  end

  def in_corner?(target)
    wall_x = [target[:x], arena_width - target[:x]].min
    wall_y = [target[:y], arena_height - target[:y]].min
    wall_x < CORNER_ZONE && wall_y < CORNER_ZONE
  end

  def target_pinned?
    return false unless @target

    wall_distance_of(@target) < PIN_THRESHOLD
  end

  def aim_and_fire(aggressive: false)
    return unless @target

    # Check alignment to target (turret tracking handles rotation)
    target_angle = if @target[:velocity_x] && @target[:velocity_y]
                     lead_angle(
                       target_x: @target[:x],
                       target_y: @target[:y],
                       velocity_x: @target[:velocity_x],
                       velocity_y: @target[:velocity_y],
                       projectile_speed: Rubowar::Config::Combat::BULLET_SPEED
                     )
                   else
                     angle_to(target_x: @target[:x], target_y: @target[:y])
                   end

    turret_diff = normalize_angle(target_angle - turret_angle).abs

    # Fire if aligned - aggressive mode has wider tolerance and lower energy threshold
    alignment_threshold = aggressive ? 25 : 18
    energy_threshold = aggressive ? 20 : 30
    return unless turret_diff < alignment_threshold && energy > energy_threshold

    fire(aggressive ? 14 : 12)
  end
end
