# frozen_string_literal: true

# A defensive rubot that circles the arena center and avoids threats.
# Uses all sensing methods: pulse for broad awareness, scan for bullets,
# and probe to check if enemies are targeting us.
class Avoider
  include Rubowar::Rubot

  size :medium # 100 HP - can win attrition wars now

  ORBIT_RADIUS_RATIO = 0.20
  ORBIT_SPEED = 4       # Reduced from 5 to conserve energy for firing
  FLEE_SPEED = 5        # Reduced from 6
  EVASIVE_SPEED_MIN = 3
  EVASIVE_SPEED_MAX = 6
  DANGER_DISTANCE_RATIO = 0.25
  WALL_BUFFER = 50
  STATIONARY_THRESHOLD = 1.5 # Target moving slower than this is "stationary"
  ENERGON_COLLECT_RANGE = 200  # How far we'll go to collect an energon
  ENERGON_MIN_VALUE_TICK = 30  # Only collect if energon has been around this long (worth ~14 energy)
  BULLET_SPEED = Rubowar::Config::Combat::BULLET_SPEED

  def on_spawn
    @mode = :orbiting
    @orbit_direction = rand > 0.5 ? 1 : -1
    @threat = nil
    @flee_angle = nil
    @evasive_ticks = 0
    @speed_phase = 0

    # Sensing state
    @sensing_mode = :pulse # Rotate through :pulse, :scan, :probe
    @incoming_bullets = []

    # Energon collection state
    @target_energon = nil
  end

  def tick
    # SENSE: Process previous results and queue new sensing
    process_sensing_results
    queue_next_sense

    # Dynamic behavior based on health and energy
    # Healthy (>50%): be aggressive, orbit and attack
    # Hurt (<50%): be defensive, flee and evade
    @defensive_mode = health < 40
    @energy_surplus = energy > 70 # Flush with energy - be aggressive!

    # MOVE + COMBAT: Mode-specific behavior
    case @mode
    when :orbiting
      orbit_tick
    when :fleeing
      flee_tick
    when :evasive
      evasive_tick
    when :collecting
      collecting_tick
    end
  end

  def on_energon(_amount)
    # Successfully collected - return to orbiting
    @target_energon = nil
    @mode = :orbiting
  end

  def on_hit(_damage, _direction)
    # Just boost shields on hit - don't change mode (detect handles evasion proactively)
    shield(8) if energy > 25 && shield_level < 50
  end

  def on_wall
    @orbit_direction *= -1
    @flee_angle = adjust_angle_from_walls(@flee_angle || rand(360)) if @mode == :fleeing || @mode == :evasive
  end

  private

  # === SENSING ===

  def process_sensing_results
    process_detect_results if detect_result
    process_pulse_results if pulse_result&.any?
    process_scan_results if scan_result&.any?
    process_probe_results if probe_result&.any?
  end

  def process_detect_results
    probed = detect_result[:probed] || 0
    scanned = detect_result[:scanned] || 0
    _pulsed = detect_result[:pulsed] || 0

    # Being probed = someone is actively targeting us with precision - EVADE NOW
    if probed.positive?
      @mode = :evasive
      @evasive_ticks = [20, @evasive_ticks].max
      @orbit_direction *= -1 # Always change direction when probed
    # Being scanned = someone's turret arc is on us - likely to fire soon
    elsif scanned.positive?
      @mode = :evasive unless @mode == :evasive
      @evasive_ticks = [12, @evasive_ticks].max
      @orbit_direction *= -1 if rand < 0.4
    end
    # Pulses are too common/broad to react to
  end

  def process_pulse_results
    rubots = pulse_result.select { |t| t[:type] == :rubot }
    bullets = pulse_result.select { |t| t[:type] == :bullet }

    # Track threats
    if rubots.any?
      closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
      dist = distance_to(closest[:x], closest[:y])

      # Update threat position but PRESERVE velocity data from scan/probe
      if @threat
        @threat[:x] = closest[:x]
        @threat[:y] = closest[:y]
      else
        @threat = closest
      end

      # Only flee if defensive OR enemy is very close
      flee_threshold = @defensive_mode ? danger_distance : danger_distance * 0.5
      if dist < flee_threshold
        @flee_angle = (angle_to(closest[:x], closest[:y]) + 180) % 360
        @mode = :fleeing unless @mode == :evasive
      end
    elsif @mode == :fleeing && @evasive_ticks <= 0
      @mode = :orbiting
      @threat = nil
    end

    # Track nearby bullets for evasion
    return unless bullets.any?

    # More cautious when defensive
    bullet_range = @defensive_mode ? 150 : 100
    nearby = bullets.select { |b| distance_to(b[:x], b[:y]) < bullet_range }
    @incoming_bullets = nearby if nearby.any?
  end

  def process_scan_results
    rubots = scan_result.select { |t| t[:type] == :rubot }
    bullets = scan_result.select { |t| t[:type] == :bullet }

    # Update threat with velocity data from scan
    if rubots.any? && @threat
      closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
      # Merge velocity data into existing threat
      @threat[:x] = closest[:x]
      @threat[:y] = closest[:y]
      @threat[:velocity_x] = closest[:velocity_x]
      @threat[:velocity_y] = closest[:velocity_y]
    end

    # Filter for dangerous bullets (headed toward us)
    return unless bullets.any?

    dangerous = bullets.select { |b| bullet_threatening?(b) }
    @incoming_bullets = dangerous if dangerous.any?
  end

  def process_probe_results
    # Update threat with probe data (includes velocity if requested)
    return unless @threat && probe_result[:x]

    @threat[:x] = probe_result[:x]
    @threat[:y] = probe_result[:y]
    @threat[:velocity_x] = probe_result[:velocity_x] if probe_result[:velocity_x]
    @threat[:velocity_y] = probe_result[:velocity_y] if probe_result[:velocity_y]

    # NOTE: We no longer check turret_angle here - detect handles evasion triggers
  end

  def queue_next_sense
    @sense_tick = (@sense_tick || 0) + 1

    # Detect EVERY tick - counts reset each tick so we can't skip
    detect if energy > 12

    # Pulse to find targets - distance must cover spawn range (50% of diagonal)
    # Pulse every 8 ticks to conserve energy for detect
    if (@sense_tick % 8).zero? && energy > 20
      pulse_dist = (arena_diagonal * 0.55).round
      pulse(distance: pulse_dist)
    end

    # Probe when turret aligned - get velocity data for leading shots
    return unless @threat && turret_aligned_with_threat? && (@sense_tick % 5).zero? && energy > 20

    probe(:position, :velocity)
  end

  def bullet_threatening?(bullet)
    return false unless bullet[:velocity_x] && bullet[:velocity_y]

    dist = distance_to(bullet[:x], bullet[:y])
    return false if dist > 150

    # Check if bullet is moving toward us
    bullet_angle = Math.atan2(bullet[:velocity_y], bullet[:velocity_x]) * 180 / Math::PI
    angle_to_us = (angle_to(bullet[:x], bullet[:y]) + 180) % 360
    angle_diff = normalize_angle(bullet_angle - angle_to_us).abs

    angle_diff < 60
  end

  # === MOVEMENT ===

  def orbit_tick
    # Check for energons to collect when safe
    if !@threat && @incoming_bullets.none? && energy < 80
      target = find_nearest_energon(max_distance: ENERGON_COLLECT_RANGE)
      if target
        @target_energon = target
        @mode = :collecting
        return collecting_tick
      end
    end

    # MOVE: Thrust and turret
    if @incoming_bullets.any?
      # Priority: dodge bullets even while orbiting
      dodge_angle = calculate_dodge_angle
      thrust(speed: FLEE_SPEED, angle: dodge_angle)
    elsif @threat
      # Orbit around the THREAT, not the center - stay at optimal range
      threat_dist = distance_to(@threat[:x], @threat[:y])
      angle_to_threat = angle_to(@threat[:x], @threat[:y])
      optimal_range = danger_distance * 1.5 # Stay just outside flee range

      orbit_angle = if threat_dist < optimal_range - 30
                      # Too close - move away while strafing
                      angle_to_threat + 180 + (30 * @orbit_direction)
                    elsif threat_dist > optimal_range + 50
                      # Too far - move closer while strafing
                      angle_to_threat + (60 * @orbit_direction)
                    else
                      # Good range - strafe perpendicular
                      angle_to_threat + (90 * @orbit_direction)
                    end

      thrust(speed: ORBIT_SPEED, angle: orbit_angle)
    else
      # No threat - orbit arena center
      center_x = arena_width / 2.0
      center_y = arena_height / 2.0

      angle_to_center = angle_to(center_x, center_y)
      dist_to_center = distance_to(center_x, center_y)

      orbit_angle = angle_to_center + (90 * @orbit_direction)

      drift_tolerance = orbit_radius * 0.2
      if dist_to_center > orbit_radius + drift_tolerance
        orbit_angle = angle_to_center
      elsif dist_to_center < orbit_radius - drift_tolerance
        orbit_angle = angle_to_center + 180
      end

      thrust(speed: ORBIT_SPEED, angle: orbit_angle)
    end

    # Aim turret at threat or sweep
    if @threat
      aim_at_threat
    else
      turret(4 * @orbit_direction)
    end

    # COMBAT: Fire at detected threats
    return unless @threat

    if @energy_surplus
      # Flush with energy - fire aggressively with bigger shots
      fire(15) if turret_aligned_with_threat? && energy > 30
      shield(5) if energy > 60 && shield_level < 60
    elsif target_stationary?
      # Stationary target - sustained fire, lower threshold (campers like Coroner/Spinner)
      fire(10) if turret_aligned_with_threat? && energy > 15
    else
      # Moving target - normal firing
      fire_threshold = @defensive_mode ? 40 : 25
      fire(10) if turret_aligned_with_threat? && energy > fire_threshold
    end
  end

  def flee_tick
    return revert_to_orbit unless @flee_angle

    # MOVE: Thrust away from threat, aim turret
    if @incoming_bullets.any?
      dodge_angle = calculate_dodge_angle
      thrust(speed: FLEE_SPEED, angle: dodge_angle)
    else
      flee_angle = near_wall? ? adjust_angle_from_walls(@flee_angle) : @flee_angle
      thrust(speed: FLEE_SPEED, angle: flee_angle)
    end

    aim_at_threat if @threat

    # COMBAT: Fire back, build shields
    if @threat
      if @energy_surplus
        fire(15) if turret_aligned_with_threat? && energy > 30
      elsif target_stationary?
        fire(10) if turret_aligned_with_threat? && energy > 15
      elsif turret_aligned_with_threat? && energy > 35
        fire(10)
      end
    end

    if @energy_surplus
      shield(6) if energy > 50 && shield_level < 50
    elsif energy > 45 && shield_level < 25
      shield(3)
    end
  end

  def evasive_tick
    @evasive_ticks -= 1

    if @evasive_ticks <= 0
      @mode = @threat ? :fleeing : :orbiting
      return
    end

    # MOVE: Unpredictable evasive maneuvers
    @speed_phase = (@speed_phase + 1) % 8
    current_speed = @speed_phase < 4 ? EVASIVE_SPEED_MIN : EVASIVE_SPEED_MAX

    # Priority: dodge bullets > evade threat > random
    if @incoming_bullets.any?
      evasive_angle = calculate_dodge_angle
    elsif @threat
      threat_angle = angle_to(@threat[:x], @threat[:y])
      perpendicular = threat_angle + (90 * (@evasive_ticks.even? ? 1 : -1))
      away_angle = threat_angle + 180
      evasive_angle = normalize_angle((perpendicular + away_angle) / 2.0)
    else
      evasive_angle = @flee_angle || rand(360)
    end

    evasive_angle = adjust_angle_from_walls(evasive_angle) if near_wall?
    thrust(speed: current_speed, angle: evasive_angle)

    aim_at_threat if @threat

    # COMBAT: Fire back, build shields
    if @threat
      if @energy_surplus
        fire(15) if turret_aligned_with_threat? && energy > 30
      elsif target_stationary?
        fire(10) if turret_aligned_with_threat? && energy > 15
      elsif turret_aligned_with_threat? && energy > 35
        fire(8)
      end
    end

    if @energy_surplus
      shield(6) if energy > 50 && shield_level < 50
    elsif energy > 50 && shield_level < 35
      shield(4)
    end
  end

  def collecting_tick
    # Abort collection if threat detected or being targeted
    if @threat || @incoming_bullets.any?
      @target_energon = nil
      @mode = :orbiting
      return orbit_tick
    end

    # Check if target energon still exists
    unless energon_still_exists?(@target_energon)
      @target_energon = nil
      @mode = :orbiting
      return
    end

    # MOVE: Head toward the energon
    energon_angle = angle_to(@target_energon[:x], @target_energon[:y])
    energon_dist = distance_to(@target_energon[:x], @target_energon[:y])

    # Slow down as we approach
    collect_speed = energon_dist < 50 ? ORBIT_SPEED : FLEE_SPEED
    thrust(speed: collect_speed, angle: energon_angle)

    # Keep turret sweeping for threats
    turret(4 * @orbit_direction)

    # No combat while collecting - focus on the prize
  end

  def calculate_dodge_angle
    return @flee_angle || rand(360) if @incoming_bullets.empty?

    # Calculate dodge direction for each bullet
    dodge_angles = @incoming_bullets.map do |b|
      bullet_to_us = angle_to(b[:x], b[:y])

      if b[:velocity_x] && b[:velocity_y]
        # With velocity: dodge perpendicular to bullet travel
        bullet_heading = Math.atan2(b[:velocity_y], b[:velocity_x]) * 180 / Math::PI
        bullet_heading + (90 * @orbit_direction)
      else
        # Without velocity: move perpendicular to bullet's line of approach
        # (assume bullet is heading toward us)
        bullet_to_us + (90 * @orbit_direction)
      end
    end

    avg_dodge = dodge_angles.sum / dodge_angles.size
    avg_dodge = adjust_angle_from_walls(avg_dodge) if near_wall?
    avg_dodge
  end

  def aim_at_threat
    return unless @threat

    target_x = @threat[:x]
    target_y = @threat[:y]

    # Lead the target
    if @threat[:velocity_x] && @threat[:velocity_y]
      dist = distance_to(target_x, target_y)
      lead_time = dist / BULLET_SPEED
      target_x += @threat[:velocity_x] * lead_time
      target_y += @threat[:velocity_y] * lead_time
    end

    target_angle = angle_to(target_x, target_y)
    turret_diff = normalize_angle(target_angle - turret_angle)
    turret(turret_diff.clamp(-20, 20))
  end

  def turret_aligned_with_threat?
    return false unless @threat

    target_angle = angle_to(@threat[:x], @threat[:y])
    turret_diff = normalize_angle(target_angle - turret_angle).abs
    turret_diff < 20
  end

  def target_stationary?
    return false unless @threat

    # Check if we have velocity data
    if @threat[:velocity_x] && @threat[:velocity_y]
      speed = Math.sqrt((@threat[:velocity_x]**2) + (@threat[:velocity_y]**2))
      speed < STATIONARY_THRESHOLD
    else
      # No velocity data - assume stationary (conservative)
      # This catches Spinner and Coroner who don't move much
      true
    end
  end

  def revert_to_orbit
    @mode = :orbiting
    @threat = nil
    @flee_angle = nil
    @evasive_ticks = 0
    @incoming_bullets = []
  end

  # === HELPERS ===

  def orbit_radius
    @orbit_radius ||= ([arena_width, arena_height].min * ORBIT_RADIUS_RATIO).round
  end

  def danger_distance
    @danger_distance ||= (arena_diagonal * DANGER_DISTANCE_RATIO).round
  end

  def arena_diagonal
    @arena_diagonal ||= Math.sqrt((arena_width**2) + (arena_height**2))
  end

  def adjust_angle_from_walls(angle)
    if x < WALL_BUFFER
      angle = rand(-45..45)
    elsif x > arena_width - WALL_BUFFER
      angle = rand(135..225)
    elsif y < WALL_BUFFER
      angle = rand(45..135)
    elsif y > arena_height - WALL_BUFFER
      angle = rand(225..315)
    end
    angle % 360
  end

  def near_wall?
    x < WALL_BUFFER || x > arena_width - WALL_BUFFER ||
      y < WALL_BUFFER || y > arena_height - WALL_BUFFER
  end
end
