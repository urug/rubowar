# frozen_string_literal: true

# A ramming tank optimized for wall damage. Herds enemies into walls/corners,
# then crushes them against the wall for sustained damage.
#
# Strategy:
# - Herd targets toward nearest wall
# - Ram them INTO the wall (perpendicular angle for max wall damage)
# - Crush: stay close and keep pushing into wall (they can't bounce away)
# - Corner traps maximize wall damage
class Crusher
  include Rubowar::Rubot

  size :large # Large = more collision damage, more HP (120), mass 1.44

  WALL_BUFFER = 80
  CORNER_RADIUS = 100
  CHARGE_DISTANCE = 180    # Start building momentum
  RAM_DISTANCE = 70        # Commit to ram
  CRUSH_DISTANCE = 50      # Stay this close when crushing
  CRUSH_BACKUP_DIST = 35   # Back up this far for repeated rams
  STUCK_SPEED_THRESHOLD = 2.0 # Enemy is "stuck" if moving slower than this
  ENERGON_COLLECT_RANGE = 200
  CRUSH_TIMEOUT = 60 # Max chronons in crush before reassessing

  def on_spawn
    @mode = :hunting
    @target = nil
    @ram_angle = nil
    @last_pulse_chronon = -100
    @target_energon = nil
    @crush_duration = 0
    @crush_phase = :ram # Oscillate between :ram and :backup for repeated hits
  end

  def act
    # Priority: wall safety (but less cautious when crushing)
    if @mode != :crushing && approaching_wall?(WALL_BUFFER)
      brake_from_wall
      return
    end

    case @mode
    when :hunting
      hunt_targets
    when :herding
      herd_to_wall
    when :charging
      charge_ram
    when :crushing
      crush_against_wall
    when :collecting
      collecting_action
    end
  end

  def on_hit(_damage, direction)
    # Attacker is behind us - acquire target
    attacker_angle = (direction + 180) % 360
    @target = {
      x: x + (Math.cos(attacker_angle * Math::PI / 180) * 150),
      y: y + (Math.sin(attacker_angle * Math::PI / 180) * 150),
      velocity_x: nil,
      velocity_y: nil
    }
    @mode = :herding
  end

  def on_collision(_other)
    # Successful ram! Switch to crushing
    if target_against_wall?(@target)
      @mode = :crushing
      @crush_phase = :backup # Just hit them, back up for another ram
    elsif @mode == :crushing
      # Not against wall yet, keep pushing
      @mode = :charging
    end
  end

  def on_wall
    # We hit a wall - reassess but don't panic if crushing
    if @mode == :charging
      @mode = :hunting
    elsif @mode == :crushing
      # Acceptable during crush - we're pushing them into wall
      @crush_duration += 1
    end
  end

  def on_energon(_amount)
    @target_energon = nil
    @mode = :hunting unless @target
  end

  private

  # === HUNTING ===

  def hunt_targets
    update_target_from_pulse

    if @target
      assess_target_position
    elsif energy < 70
      find_energon
    else
      patrol_for_targets
    end
  end

  def update_target_from_pulse
    return if chronons - @last_pulse_chronon < 8

    pulse(distance: 400)
    @last_pulse_chronon = chronons

    return unless pulse_result

    rubots = pulse_result.select { |t| t[:type] == :rubot }
    return if rubots.empty?

    # Prioritize: stuck against wall > near corner > near wall > closest
    @target = rubots.min_by do |t|
      dist = distance_to(t[:x], t[:y])
      wall_dist = target_wall_distance(t)

      # Huge bonus for wall-stuck enemies (easy to crush)
      stuck_bonus = wall_dist < 30 ? -200 : 0
      corner_bonus = target_near_corner?(t) ? -150 : 0
      wall_bonus = wall_dist < WALL_BUFFER ? -80 : 0

      dist + stuck_bonus + corner_bonus + wall_bonus
    end

    @mode = :herding if @target
  end

  def assess_target_position
    wall_dist = target_wall_distance(@target)

    if target_against_wall?(@target)
      # They're stuck! Go straight for the crush
      @ram_angle = perpendicular_wall_angle(@target)
      @mode = :charging
    elsif target_near_corner?(@target)
      # Corner trap - ram into corner
      @ram_angle = corner_ram_angle(@target)
      @mode = :charging
    elsif wall_dist < WALL_BUFFER * 1.5
      # Near a wall - ram perpendicular to maximize wall damage
      @ram_angle = perpendicular_wall_angle(@target)
      @mode = :charging
    else
      # Open field - herd them toward nearest wall
      @mode = :herding
    end
  end

  def patrol_for_targets
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)

    if momentum_aligned?(center_angle, tolerance: 45)
      thrust(speed: 3, angle: center_angle) if speed < 8
    else
      thrust(speed: 3, angle: center_angle)
    end

    turret(10)
    shield(3) if energy > 50 && shield_level < 30
  end

  # === HERDING ===

  def herd_to_wall
    return revert_to_hunting unless @target

    update_target_from_probe
    dist = distance_to(@target[:x], @target[:y])

    # Determine which wall to herd toward
    herd_angle = calculate_herd_angle

    if dist > CHARGE_DISTANCE
      position_for_herd(herd_angle)
    elsif target_wall_distance(@target) < WALL_BUFFER * 2
      # Close enough to wall - charge!
      @ram_angle = perpendicular_wall_angle(@target)
      @mode = :charging
    else
      push_toward_wall(herd_angle)
    end

    aim_turret_at_target
    # Heavy shields during approach - absorb fire from corner campers
    shield(10) if energy > 30 && shield_level < 80
  end

  def calculate_herd_angle
    wall = nearest_wall_to_target(@target)
    case wall
    when :left then 180
    when :right then 0
    when :bottom then 270
    when :top then 90
    end
  end

  def position_for_herd(herd_angle)
    opposite_angle = (herd_angle + 180) % 360
    ideal_x = @target[:x] + (Math.cos(opposite_angle * Math::PI / 180) * 150)
    ideal_y = @target[:y] + (Math.sin(opposite_angle * Math::PI / 180) * 150)

    ideal_x = ideal_x.clamp(WALL_BUFFER, arena_width - WALL_BUFFER)
    ideal_y = ideal_y.clamp(WALL_BUFFER, arena_height - WALL_BUFFER)

    move_angle = angle_to(ideal_x, ideal_y)
    move_toward(move_angle, 4)
  end

  def push_toward_wall(herd_angle)
    push_angle = angle_to(@target[:x], @target[:y])
    blended_angle = blend_angles(push_angle, herd_angle, 0.4)
    move_toward(blended_angle, 5)
  end

  # === CHARGING ===

  def charge_ram
    return revert_to_hunting unless @target && @ram_angle

    update_target_from_probe
    dist = distance_to(@target[:x], @target[:y])

    # Check if target is already stuck - go straight to crushing
    if target_against_wall?(@target) && dist < RAM_DISTANCE
      @mode = :crushing
      @crush_duration = 0
      return
    end

    if dist > RAM_DISTANCE
      build_momentum
    else
      commit_to_ram
    end

    aim_turret_at_target
    # Maximum shields during charge - absorb damage before impact
    shield(12) if energy > 25 && shield_level < 90
  end

  def build_momentum
    # Recalculate optimal ram angle
    @ram_angle = if target_near_corner?(@target)
                   corner_ram_angle(@target)
                 else
                   perpendicular_wall_angle(@target)
                 end

    if momentum_aligned?(@ram_angle, tolerance: 30)
      thrust(speed: 6, angle: @ram_angle) if speed < 16
    elsif speed > 8
      brake_thrust
    else
      thrust(speed: 5, angle: @ram_angle)
    end
  end

  def commit_to_ram
    direct_angle = angle_to(@target[:x], @target[:y])

    if momentum_aligned?(direct_angle, tolerance: 45)
      thrust(speed: 7, angle: direct_angle) if speed < 18
    else
      thrust(speed: 5, angle: direct_angle)
    end
  end

  # === CRUSHING (signature move) ===
  # Oscillates between ramming and backing up for repeated collision damage
  # Also shoots while crushing for extra damage

  def crush_against_wall
    return revert_to_hunting unless @target

    update_target_from_probe
    dist = distance_to(@target[:x], @target[:y])
    @crush_duration += 1

    # Crush timeout or target escaped wall
    if @crush_duration > CRUSH_TIMEOUT || !target_against_wall?(@target)
      @mode = :charging
      @ram_angle = angle_to(@target[:x], @target[:y])
      @crush_duration = 0
      return
    end

    # Aim turret and SHOOT while crushing - free damage!
    aim_turret_at_target
    fire_at_pinned_target

    # Oscillate between ram and backup phases for repeated collision damage
    case @crush_phase
    when :ram
      crush_ram_phase(dist)
    when :backup
      crush_backup_phase(dist)
    end

    # Moderate shields during crush
    shield(4) if energy > 25 && shield_level < 40
  end

  def crush_ram_phase(dist)
    if dist < CRUSH_BACKUP_DIST
      # Very close - switch to backup for another hit
      @crush_phase = :backup
    else
      # Ram into them aggressively
      direct_angle = angle_to(@target[:x], @target[:y])
      thrust(speed: 6, angle: direct_angle) if speed < 12
    end
  end

  def crush_backup_phase(dist)
    if dist > CRUSH_DISTANCE
      # Far enough - ram again!
      @crush_phase = :ram
    else
      # Back up perpendicular to wall (away from target)
      backup_angle = (angle_to(@target[:x], @target[:y]) + 180) % 360
      # Don't back into center too far - stay close
      thrust(speed: 4, angle: backup_angle) if dist < CRUSH_DISTANCE
    end
  end

  def fire_at_pinned_target
    return unless @target

    target_angle = angle_to(@target[:x], @target[:y])
    turret_diff = normalize_angle(target_angle - turret_angle).abs
    dist = distance_to(@target[:x], @target[:y])

    # Fire when reasonably aligned - pinned targets are easy to hit
    return unless turret_diff < 25 && dist < 100 && energy > 20

    fire(10) # Medium power shots while grinding
  end

  # === ENERGON COLLECTION ===

  def find_energon
    energon = find_nearest_energon(max_distance: ENERGON_COLLECT_RANGE)
    if energon
      @target_energon = energon
      @mode = :collecting
    else
      patrol_for_targets
    end
  end

  def collecting_action
    update_target_from_pulse
    if @target
      @target_energon = nil
      @mode = :herding
      return
    end

    unless energon_still_exists?(@target_energon)
      @target_energon = nil
      @mode = :hunting
      return
    end

    energon_angle = angle_to(@target_energon[:x], @target_energon[:y])
    safe_angle = safe_movement_angle(energon_angle)

    move_toward(safe_angle, 4)
    turret(8)
    shield(3) if energy > 50 && shield_level < 30
  end

  # === HELPERS ===

  def revert_to_hunting
    @mode = :hunting
    @target = nil
    @ram_angle = nil
    @crush_duration = 0
    @crush_phase = :ram
  end

  def update_target_from_probe
    return unless @target

    turret_diff = normalize_angle(angle_to(@target[:x], @target[:y]) - turret_angle)
    return unless turret_diff.abs < 20 && energy > 10

    probe(:position, :velocity)
    return unless probe_result&.any?

    @target = {
      x: probe_result[:x],
      y: probe_result[:y],
      velocity_x: probe_result[:velocity_x],
      velocity_y: probe_result[:velocity_y]
    }
  end

  def aim_turret_at_target
    return unless @target

    target_angle = angle_to(@target[:x], @target[:y])
    turret_diff = normalize_angle(target_angle - turret_angle)
    turret(turret_diff.clamp(-15, 15))
  end

  def move_toward(angle, thrust_speed)
    safe_angle = safe_movement_angle(angle)

    if momentum_aligned?(safe_angle, tolerance: 45)
      thrust(speed: thrust_speed, angle: safe_angle) if speed < 15
    elsif speed > 8
      brake_thrust
    else
      thrust(speed: thrust_speed, angle: safe_angle)
    end
  end

  def brake_thrust
    return unless velocity_angle

    brake_angle = (velocity_angle + 180) % 360
    thrust(speed: 4, angle: brake_angle)
  end

  def brake_from_wall
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    thrust(speed: 4, angle: center_angle)
  end

  def safe_movement_angle(angle)
    return angle if wall_distance(angle) > WALL_BUFFER * 1.5

    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    diff = normalize_angle(center_angle - angle)
    (angle + (diff * 0.6)) % 360
  end

  # === WALL/CORNER GEOMETRY ===

  def target_against_wall?(target)
    return false unless target

    target_wall_distance(target) < 40
  end

  def target_is_stuck?(target)
    return false unless target && target[:velocity_x] && target[:velocity_y]

    target_speed = Math.sqrt((target[:velocity_x]**2) + (target[:velocity_y]**2))
    target_against_wall?(target) && target_speed < STUCK_SPEED_THRESHOLD
  end

  def corners
    @corners ||= [
      { x: CORNER_RADIUS, y: CORNER_RADIUS },
      { x: arena_width - CORNER_RADIUS, y: CORNER_RADIUS },
      { x: CORNER_RADIUS, y: arena_height - CORNER_RADIUS },
      { x: arena_width - CORNER_RADIUS, y: arena_height - CORNER_RADIUS }
    ]
  end

  def target_near_corner?(target)
    return false unless target

    corners.any? do |corner|
      dx = target[:x] - corner[:x]
      dy = target[:y] - corner[:y]
      Math.sqrt((dx * dx) + (dy * dy)) < CORNER_RADIUS
    end
  end

  def nearest_corner_to(target)
    corners.min_by do |corner|
      dx = target[:x] - corner[:x]
      dy = target[:y] - corner[:y]
      Math.sqrt((dx * dx) + (dy * dy))
    end
  end

  def corner_ram_angle(target)
    corner = nearest_corner_to(target)
    angle_to(corner[:x], corner[:y])
  end

  def target_wall_distance(target)
    return Float::INFINITY unless target

    [
      target[:x],
      arena_width - target[:x],
      target[:y],
      arena_height - target[:y]
    ].min
  end

  def nearest_wall_to_target(target)
    distances = {
      left: target[:x],
      right: arena_width - target[:x],
      bottom: target[:y],
      top: arena_height - target[:y]
    }
    distances.min_by { |_, d| d }.first
  end

  # Ram perpendicular to the nearest wall for maximum wall impact damage
  def perpendicular_wall_angle(target)
    wall = nearest_wall_to_target(target)
    case wall
    when :left then 180   # Push west into left wall
    when :right then 0    # Push east into right wall
    when :bottom then 270 # Push south into bottom wall
    when :top then 90     # Push north into top wall
    end
  end

  def blend_angles(angle1, angle2, weight)
    rad1 = angle1 * Math::PI / 180
    rad2 = angle2 * Math::PI / 180

    x_val = (Math.cos(rad1) * (1 - weight)) + (Math.cos(rad2) * weight)
    y_val = (Math.sin(rad1) * (1 - weight)) + (Math.sin(rad2) * weight)

    Math.atan2(y_val, x_val) * 180 / Math::PI
  end
end
