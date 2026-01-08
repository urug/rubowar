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

  def on_hit(damage, direction)
    shield(8) if energy > 30 && shield_level < 50

    # If hit while searching, find the attacker
    return unless @mode == :searching

    attacker_angle = (direction + 180) % 360
    @target = {
      x: x + Math.cos(attacker_angle * Math::PI / 180) * 150,
      y: y + Math.sin(attacker_angle * Math::PI / 180) * 150
    }
    @mode = :hunting # Default to hunting until we know their size
  end

  def on_wall
    # Bounce away from wall
    center_angle = angle_to(arena_width / 2, arena_height / 2)
    thrust(speed: 4, angle: center_angle)
  end

  private

  def sense_environment
    # Pulse for broad awareness
    return if chronons - @last_pulse < 10

    pulse(distance: PULSE_RANGE)
    @last_pulse = chronons

    return unless pulse_result&.any?

    rubots = pulse_result.select { |t| t[:type] == :rubot }
    return if rubots.empty?

    # Pick closest target
    closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }

    if @target.nil? || distance_to(closest[:x], closest[:y]) < distance_to(@target[:x], @target[:y])
      @target = closest
      determine_tactics
    end
  end

  def determine_tactics
    return unless @target

    # Probe to learn target size and health
    aim_at_target

    if turret_aligned? && energy > 12
      probe(:position, :velocity, :size, :health)

      if probe_result&.any?
        @target = @target.merge(probe_result)
        @target_size = probe_result[:size]
        @target_health = probe_result[:health]

        # Choose tactics based on size
        case @target_size
        when :small
          @mode = :hunting   # Aggressive - they're fragile
        when :large
          @mode = @target_health && @target_health < WEAK_THRESHOLD ? :finishing : :kiting
        else
          @mode = :hunting   # Medium - standard aggression
        end
      end
    end

    # Default to hunting if we can't probe
    @mode = :hunting if @mode == :searching
  end

  def search_for_prey
    # Opportunistically collect nearby energon while searching
    if collect_nearby_energon?
      move_to_energon
    elsif distance_to(arena_width / 2, arena_height / 2) > 200
      # Patrol toward center
      center_angle = angle_to(arena_width / 2, arena_height / 2)
      thrust(speed: 4, angle: center_angle) if speed < 10
    else
      # Circle in center
      thrust(speed: 3, angle: (chronons * 3) % 360) if speed < 6
    end

    turret(12)
    shield(4) if energy > 60 && shield_level < 30
  end

  def hunt_prey
    return search_mode unless @target

    update_target
    check_for_mode_switch

    dist = distance_to(@target[:x], @target[:y])

    # Close in aggressively
    if dist > HUNT_RANGE
      pursuit_angle = calculate_intercept_angle
      thrust(speed: 6, angle: safe_angle(pursuit_angle)) if speed < 14
    elsif dist < MIN_RANGE
      # Too close - back off slightly for better aim
      backup_angle = (angle_to(@target[:x], @target[:y]) + 180) % 360
      thrust(speed: 3, angle: backup_angle)
    else
      # Good range - maintain position
      thrust(speed: 2, angle: angle_to(@target[:x], @target[:y])) if speed < 5
    end

    # Aggressive fire
    aim_and_fire(power: 15)
    shield(6) if energy > 40 && shield_level < 40
  end

  def kite_prey
    return search_mode unless @target

    update_target
    check_for_mode_switch

    dist = distance_to(@target[:x], @target[:y])

    # Maintain kite range
    if dist < KITE_RANGE - 30
      # Too close - back away
      escape_angle = (angle_to(@target[:x], @target[:y]) + 180) % 360
      escape_angle = safe_angle(escape_angle)
      thrust(speed: 6, angle: escape_angle) if speed < 12
    elsif dist > KITE_RANGE + 50
      # Too far - close in a bit
      approach_angle = safe_angle(angle_to(@target[:x], @target[:y]))
      thrust(speed: 4, angle: approach_angle) if speed < 10
    else
      # Good range - strafe to make ourselves harder to hit
      strafe_angle = angle_to(@target[:x], @target[:y]) + 90
      strafe_angle = safe_angle(strafe_angle)
      thrust(speed: 3, angle: strafe_angle) if speed < 8
    end

    # Consistent chip damage
    aim_and_fire(power: 12)
    # Higher shields when kiting - we're taking fire
    shield(10) if energy > 35 && shield_level < 70
  end

  def finish_prey
    return search_mode unless @target

    update_target

    # If they healed up, go back to kiting
    if @target_health && @target_health >= WEAK_THRESHOLD
      @mode = @target_size == :large ? :kiting : :hunting
      return
    end

    dist = distance_to(@target[:x], @target[:y])

    # Close in for the kill
    if dist > HUNT_RANGE
      pursuit_angle = calculate_intercept_angle
      thrust(speed: 7, angle: safe_angle(pursuit_angle)) if speed < 16
    else
      # In kill range - stay on them
      thrust(speed: 4, angle: angle_to(@target[:x], @target[:y])) if speed < 8
    end

    # Maximum aggression
    aim_and_fire(power: 20)
    shield(5) if energy > 25 && shield_level < 40
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

    # Probe periodically for health updates
    if turret_aligned? && energy > 10 && (chronons % 15 == 0)
      probe(:position, :velocity, :health)
      if probe_result&.any?
        @target = @target.merge(probe_result)
        @target_health = probe_result[:health]
      end
    end
  end

  def aim_at_target
    return unless @target
    target_angle = angle_to(@target[:x], @target[:y])
    turret_diff = normalize_angle(target_angle - turret_angle)
    turret(turret_diff.clamp(-20, 20))
  end

  def turret_aligned?
    return false unless @target
    target_angle = angle_to(@target[:x], @target[:y])
    normalize_angle(target_angle - turret_angle).abs < 15
  end

  def aim_and_fire(power:)
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
    turret(turret_diff.clamp(-20, 20))

    # Fire when aligned
    return unless turret_diff.abs < 18 && energy > power + 10
    fire(power)
  end

  def calculate_intercept_angle
    return angle_to(@target[:x], @target[:y]) unless @target[:velocity_x] && @target[:velocity_y]

    lead_angle(
      @target[:x], @target[:y],
      @target[:velocity_x], @target[:velocity_y],
      projectile_speed: 15 # Approximate our closing speed
    )
  end

  def safe_angle(angle)
    # Avoid walls
    wall_dist = wall_distance(angle)
    return angle if wall_dist > 100

    center_angle = angle_to(arena_width / 2, arena_height / 2)
    diff = normalize_angle(center_angle - angle)
    (angle + diff * 0.5) % 360
  end

  def search_mode
    @mode = :searching
    @target = nil
    @target_size = nil
    @target_health = nil
  end

  def collect_nearby_energon?
    # Only check for energon after they've had time to spawn
    return false if chronons < energon_spawn_interval

    # Only collect if we could use the energy
    return false if energy > 70

    @nearest_energon = find_nearest_energon(max_distance: ENERGON_RANGE)
    @nearest_energon != nil
  end

  def move_to_energon
    return unless @nearest_energon

    energon_angle = angle_to(@nearest_energon[:x], @nearest_energon[:y])
    thrust(speed: 4, angle: energon_angle) if speed < 8
  end
end
