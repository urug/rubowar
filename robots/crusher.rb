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

  def on_collision(other)
    # Successful ram - if they're pinned, start crushing
    return unless @target

    if target_pinned?
      @mode = :crushing
      @crush_start = chronons
    end
  end

  def on_hit(_damage, direction)
    # Someone's shooting us - find them and ram them
    return if @target && @mode == :crushing

    attacker_angle = (direction + 180) % 360
    @target = {
      x: x + Math.cos(attacker_angle * Math::PI / 180) * 150,
      y: y + Math.sin(attacker_angle * Math::PI / 180) * 150
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
    return if chronons - @last_pulse < 8

    pulse(distance: 400)
    @last_pulse = chronons
    return unless pulse_result&.any?

    rubots = pulse_result.select { |t| t[:type] == :rubot }
    return if rubots.empty?

    # Prioritize: corner-trapped > wall-adjacent > closest
    @target = rubots.min_by do |t|
      dist = distance_to(t[:x], t[:y])
      wall_dist = wall_distance_of(t)

      # Huge priority for corner-trapped targets
      corner_bonus = in_corner?(t) ? -300 : 0
      # High priority for wall-adjacent targets
      wall_bonus = wall_dist < WALL_DANGER ? -150 : 0

      dist + corner_bonus + wall_bonus
    end

    @mode = :positioning if @target && @mode == :hunting
  end

  def hunt
    # No target - patrol toward center, scan around
    center_angle = angle_to(arena_width / 2, arena_height / 2)

    if distance_to(arena_width / 2, arena_height / 2) > 150
      thrust(speed: 4, angle: center_angle) if speed < 8
    end

    turret(15)
    shield(5) if energy > 60 && shield_level < 30
  end

  def position_for_ram
    return hunt unless @target

    update_target_position
    dist = distance_to(@target[:x], @target[:y])

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
      approach_angle = angle_to(@target[:x], @target[:y])
      thrust(speed: 5, angle: approach_angle) if speed < 12
    else
      # In range - position for wall ram
      thrust(speed: 6, angle: ram_angle) if speed < 14
    end

    # Fire while closing
    aim_and_fire
    # Moderate shields
    shield(8) if energy > 50 && shield_level < 60
  end

  def execute_ram
    return hunt unless @target

    update_target_position

    # Check if target is now pinned
    if target_pinned?
      @mode = :crushing
      @crush_start = chronons
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
    shield(12) if energy > 40 && shield_level < 80
  end

  def crush_pinned_target
    return hunt unless @target

    update_target_position
    dist = distance_to(@target[:x], @target[:y])

    # Stop crushing if: target escaped, timeout, or target dead (no update)
    if !target_pinned? || (chronons - @crush_start) > 60
      @mode = :positioning
      @crush_start = nil
      return
    end

    # Ram them into the wall repeatedly
    if dist > CRUSH_RANGE
      # Close in for another ram
      ram_angle = angle_to(@target[:x], @target[:y])
      thrust(speed: 6, angle: ram_angle) if speed < 12
    elsif dist < 25
      # Too close, back up slightly for momentum
      backup_angle = (angle_to(@target[:x], @target[:y]) + 180) % 360
      thrust(speed: 3, angle: backup_angle)
    else
      # Perfect range - ram into wall
      ram_angle = calculate_ram_angle
      thrust(speed: 7, angle: ram_angle) if speed < 15
    end

    # Fire at pinned target - easy hits
    aim_and_fire(aggressive: true)
    shield(6) if energy > 35 && shield_level < 50
  end

  # Calculate angle that pushes target INTO their nearest wall
  # We need to hit them from the opposite side of their nearest wall
  def calculate_ram_angle
    return angle_to(@target[:x], @target[:y]) unless @target

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
    dist_to_ideal = Math.sqrt((x - ideal_x)**2 + (y - ideal_y)**2)
    dist_to_target = distance_to(@target[:x], @target[:y])

    if dist_to_ideal < 60 || dist_to_target < RAM_COMMIT
      # In position or close enough - ram directly
      angle_to(@target[:x], @target[:y])
    else
      # Move toward attack position
      angle_to(ideal_x.clamp(50, arena_width - 50), ideal_y.clamp(50, arena_height - 50))
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

  def update_target_position
    return unless @target

    # Use probe for precise tracking when aligned
    target_angle = angle_to(@target[:x], @target[:y])
    turret_diff = normalize_angle(target_angle - turret_angle).abs

    if turret_diff < 20 && energy > 10
      probe(:position, :velocity)
      if probe_result&.any?
        @target = {
          x: probe_result[:x],
          y: probe_result[:y],
          velocity_x: probe_result[:velocity_x],
          velocity_y: probe_result[:velocity_y]
        }
      end
    end
  end

  def aim_and_fire(aggressive: false)
    return unless @target

    # Lead moving targets
    if @target[:velocity_x] && @target[:velocity_y]
      target_angle = lead_angle(
        @target[:x], @target[:y],
        @target[:velocity_x], @target[:velocity_y],
        projectile_speed: Rubowar::Config::Combat::BULLET_SPEED
      )
    else
      target_angle = angle_to(@target[:x], @target[:y])
    end

    turret_diff = normalize_angle(target_angle - turret_angle)
    turret(turret_diff.clamp(-15, 15))

    dist = distance_to(@target[:x], @target[:y])
    threshold = aggressive ? 25 : 15
    min_energy = aggressive ? 20 : 35

    return unless turret_diff.abs < threshold && energy > min_energy

    power = aggressive ? 15 : 10
    fire(power)
  end
end
