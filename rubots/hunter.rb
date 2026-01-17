# frozen_string_literal: true

# An adaptive predator that adjusts tactics based on prey size.
#
# Strategy:
# - vs Small: Hunt aggressively - they can't take hits
# - vs Large: Kite at range - chip damage until weak, then finish
# - vs Medium: Balanced approach
#
# The hunter becomes the hunted's worst nightmare by exploiting size mismatches.
class Hunter
  include Rubowar::Rubot

  size :medium # 100 HP, balanced stats

  KITE_RANGE = 180        # Ideal distance when kiting large targets
  HUNT_RANGE = 100        # Close range for hunting small targets
  MIN_RANGE = 60          # Back off if closer than this
  WEAK_THRESHOLD = 40     # Target is "weak" below this HP
  PULSE_RANGE = 400
  ENERGON_RANGE = 120     # Only grab nearby energon

  def on_spawn
    @mode = :searching
    @target = nil
    @target_size = nil
    @last_pulse = -100
    @nearest_energon = nil
  end

  def act
    sense_environment
    track_target

    case @mode
    when :searching
      search_for_prey
    when :hunting
      hunt_prey      # Aggressive close-range pursuit
    when :kiting
      kite_prey      # Maintain distance, chip damage
    when :finishing
      finish_prey    # Target is weak, close in for kill
    end
  end

  def on_hit(damage:, direction:)
    raise_shields(8) if energy > 30 && shield_level < 50

    # If hit while searching, find the attacker
    return unless @mode == :searching

    attacker_angle = (direction + 180) % 360
    @target = {
      x: x + (Math.cos(attacker_angle * Math::PI / 180) * 150),
      y: y + (Math.sin(attacker_angle * Math::PI / 180) * 150)
    }
    @mode = :hunting # Default to hunting until we know their size
  end

  def on_wall
    # Bounce away from wall
    center_angle = angle_to(target_x: arena_width / 2, target_y: arena_height / 2)
    thrust(speed: 4, angle: center_angle)
  end

  private

  def sense_environment
    # Pulse for broad awareness every 10 ticks
    if chronon - @last_pulse >= 10
      pulse(distance: PULSE_RANGE)
      @last_pulse = chronon

      if pulse_echo.any_rubots?
        closest = pulse_echo.closest_rubot(to_x: x, to_y: y)

        # Always update to closest target (handles target switching after kill)
        @target = { x: closest.x, y: closest.y }
        determine_tactics
      elsif @target
        # No rubots found - target is dead, search for new one
        search_mode
      end
    end

    # Use scan to get velocity data for better tracking
    update_target_from_scan if @target && energy > 12
  end

  def update_target_from_scan
    scan(angle: 50, distance: 300, velocity: true)
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

    # Rotate faster when far off, slower when close for precision
    max_rotation = turret_diff.abs > 40 ? 20 : 15
    rotate_turret(turret_diff.clamp(-max_rotation, max_rotation))
  end

  def determine_tactics
    return unless @target

    # Probe to learn target size and health when aligned
    if turret_aligned? && energy > 12
      probe(:size, :health)

      if probe_echo.found?
        @target_size = probe_echo.size
        @target_health = probe_echo.health

        # Choose tactics based on size
        @mode = case @target_size
                when :small
                  :hunting   # Aggressive - they're fragile
                when :large
                  @target_health && @target_health < WEAK_THRESHOLD ? :finishing : :kiting
                else
                  :hunting   # Medium - standard aggression
                end
        return
      end
    end

    # Default to hunting if we can't probe yet
    @mode = :hunting if @mode == :searching
  end

  def search_for_prey
    # Opportunistically collect nearby energon while searching
    if collect_nearby_energon?
      move_to_energon
    elsif distance_to(target_x: arena_width / 2, target_y: arena_height / 2) > 200
      # Patrol toward center
      center_angle = angle_to(target_x: arena_width / 2, target_y: arena_height / 2)
      thrust(speed: 4, angle: center_angle) if speed < 10
    elsif speed < 6
      # Circle in center
      thrust(speed: 3, angle: (chronon * 3) % 360)
    end

    rotate_turret(12)
    raise_shields(4) if energy > 60 && shield_level < 30
  end

  def hunt_prey
    return search_mode unless @target

    update_target
    check_for_mode_switch

    dist = distance_to(target_x: @target[:x], target_y: @target[:y])

    # Close in aggressively
    if dist > HUNT_RANGE
      pursuit_angle = calculate_intercept_angle
      thrust(speed: 6, angle: safe_angle(pursuit_angle)) if speed < 14
    elsif dist < MIN_RANGE
      # Too close - back off slightly for better aim
      backup_angle = (angle_to(target_x: @target[:x], target_y: @target[:y]) + 180) % 360
      thrust(speed: 3, angle: backup_angle)
    elsif speed < 5
      # Good range - maintain position
      thrust(speed: 2, angle: angle_to(target_x: @target[:x], target_y: @target[:y]))
    end

    # Aggressive fire
    aim_and_fire(power: 15)
    raise_shields(6) if energy > 40 && shield_level < 40
  end

  def kite_prey
    return search_mode unless @target

    update_target
    check_for_mode_switch

    dist = distance_to(target_x: @target[:x], target_y: @target[:y])

    # Maintain kite range - use thrust_cost to budget energy for combat
    if dist < KITE_RANGE - 30
      # Too close - back away (priority escape, spend more if needed)
      escape_angle = (angle_to(target_x: @target[:x], target_y: @target[:y]) + 180) % 360
      escape_angle = safe_angle(escape_angle)
      thrust(speed: 6, angle: escape_angle) if speed < 12
    elsif dist > KITE_RANGE + 50
      # Too far - close in a bit
      approach_angle = safe_angle(angle_to(target_x: @target[:x], target_y: @target[:y]))
      thrust(speed: 4, angle: approach_angle) if speed < 10
    else
      # Good range - strafe to make ourselves harder to hit
      # Use thrust_cost to ensure we keep enough energy for fire + shields
      strafe_angle = angle_to(target_x: @target[:x], target_y: @target[:y]) + 90
      strafe_angle = safe_angle(strafe_angle)
      move_cost = thrust_cost(thrust_speed: 3, angle: strafe_angle)
      # Reserve: 12 for fire + 10 for shields + buffer
      thrust(speed: 3, angle: strafe_angle) if speed < 8 && move_cost <= energy - 30
    end

    # Consistent chip damage
    aim_and_fire(power: 12)
    # Higher shields when kiting - we're taking fire
    raise_shields(10) if energy > 35 && shield_level < 70
  end

  def finish_prey
    return search_mode unless @target

    update_target

    # If they healed up, go back to kiting
    if @target_health && @target_health >= WEAK_THRESHOLD
      @mode = @target_size == :large ? :kiting : :hunting
      return
    end

    dist = distance_to(target_x: @target[:x], target_y: @target[:y])

    # Close in for the kill
    if dist > HUNT_RANGE
      pursuit_angle = calculate_intercept_angle
      thrust(speed: 7, angle: safe_angle(pursuit_angle)) if speed < 16
    elsif speed < 8
      # In kill range - stay on them
      thrust(speed: 4, angle: angle_to(target_x: @target[:x], target_y: @target[:y]))
    end

    # Maximum aggression
    aim_and_fire(power: 20)
    raise_shields(5) if energy > 25 && shield_level < 40
  end

  def check_for_mode_switch
    return unless @target_size == :large && @target_health

    if @target_health < WEAK_THRESHOLD && @mode == :kiting
      @mode = :finishing
    elsif @target_health >= WEAK_THRESHOLD && @mode == :finishing
      @mode = :kiting
    end
  end

  def update_target
    return unless @target

    # Probe periodically for health updates (position handled by scan)
    return unless turret_aligned? && energy > 8 && (chronon % 12).zero?

    probe(:health)
    if probe_echo.found?
      @target_health = probe_echo.health
    else
      # Target not found - they're dead or moved, clear and search for new target
      search_mode
    end
  end

  def turret_aligned?
    return false unless @target

    target_angle = angle_to(target_x: @target[:x], target_y: @target[:y])
    normalize_angle(target_angle - turret_angle).abs < 15
  end

  def aim_and_fire(power:)
    return unless @target

    # Check alignment (turret tracking handles rotation)
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

    # Fire when aligned
    return unless turret_diff < 18 && energy > power + 8

    fire(power)
  end

  def calculate_intercept_angle
    return angle_to(target_x: @target[:x], target_y: @target[:y]) unless @target[:velocity_x] && @target[:velocity_y]

    lead_angle(
      target_x: @target[:x],
      target_y: @target[:y],
      velocity_x: @target[:velocity_x],
      velocity_y: @target[:velocity_y],
      projectile_speed: 15 # Approximate our closing speed
    )
  end

  def safe_angle(angle)
    # Avoid walls
    wall_dist = wall_distance(angle)
    return angle if wall_dist > 100

    center_angle = angle_to(target_x: arena_width / 2, target_y: arena_height / 2)
    diff = normalize_angle(center_angle - angle)
    (angle + (diff * 0.5)) % 360
  end

  def search_mode
    @mode = :searching
    @target = nil
    @target_size = nil
    @target_health = nil
  end

  def collect_nearby_energon?
    # Only check for energon after they've had time to spawn
    return false if chronon < energon_spawn_interval

    # Only collect if we could use the energy
    return false if energy > 70

    @nearest_energon = find_nearest_energon(max_distance: ENERGON_RANGE)
    @nearest_energon != nil
  end

  def move_to_energon
    return unless @nearest_energon

    energon_angle = angle_to(target_x: @nearest_energon[:x], target_y: @nearest_energon[:y])
    thrust(speed: 4, angle: energon_angle) if speed < 8
  end
end
