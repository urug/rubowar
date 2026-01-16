# frozen_string_literal: true

# A wall-hugging evader with minimal movement philosophy.
#
# Strategy:
# - Small hitbox = micro-adjustments suffice (slip punches, don't jump around)
# - Slow drift along walls, detect when targeted, tiny dodge to slip bullets
# - Stick-and-move: plant feet to aim, fire, resume drifting
# - Patient shots - save energy, fire big when aligned
#
# Strengths: Energy efficient, stable aim, hard to hit despite slow movement
# Weaknesses: Low HP means mistakes are costly, struggles vs patient snipers
class Hugger
  include Rubowar::Rubot

  size :small

  WALL_DIST = 50
  CORNER_ZONE = 120
  PLANT_DURATION = 8
  PLANT_COOLDOWN = 15

  def on_spawn
    @wall = nearest_wall
    @direction = rand > 0.5 ? 1 : -1
    @target = nil
    @juke_timer = rand(20..35)
    @evading = 0
    @last_scan = -100
    @plant_timer = 0
  end

  def act
    check_if_targeted
    sense_environment
    move
    aim_and_fire
    detect
  end

  def on_hit(damage:, direction:)
    @evading = 15
    @direction *= -1
    raise_shields(8) if energy > 25 && shield_level < 50
  end

  def on_wall
    @direction *= -1
    @wall = nearest_wall
  end

  private

  # ---------- Sensing ----------

  def check_if_targeted
    update_juke_timer

    return unless detect_intel.targeted?

    if detect_intel.probed.positive?
      start_evasion(8)
    elsif detect_intel.scanned.positive?
      start_evasion(5) if rand < 0.5
    end
  end

  def update_juke_timer
    @juke_timer -= 1
    return unless @juke_timer <= 0

    @direction *= -1
    @juke_timer = rand(20..35)
  end

  def start_evasion(duration)
    @evading = duration
    @evade_angle = random_wall_parallel_angle
  end

  def sense_environment
    return if chronons - @last_scan < 8

    @last_scan = chronons
    scan_for_targets
    update_safe_wall
  end

  def scan_for_targets
    scan_opposite_corners
    process_scan_echos unless scan_echo.empty?

    return unless @target.nil? || (chronons % 16).zero?

    pulse(distance: 300)
    process_pulse_echos unless pulse_echo.empty?
  end

  def process_scan_echos
    check_incoming_bullets(scan_echo.bullets) if scan_echo.any_bullets?

    return unless scan_echo.any_rubots?

    closest = scan_echo.closest_rubot(to_x: x, to_y: y)
    @target = { x: closest.x, y: closest.y, velocity_x: closest.velocity_x, velocity_y: closest.velocity_y }
  end

  def process_pulse_echos
    return unless pulse_echo.any_rubots?

    closest = pulse_echo.closest_rubot(to_x: x, to_y: y)
    @target = { x: closest.x, y: closest.y }
  end

  def update_safe_wall
    return unless @target && target_in_corner?

    safe = safe_wall_from_corner
    @wall = safe if @wall != safe
  end

  def check_incoming_bullets(bullets)
    bullets.each do |bullet|
      next unless bullet_heading_toward_us?(bullet)

      start_evasion(12)
      break
    end
  end

  def bullet_heading_toward_us?(bullet)
    dist = distance_to(target_x: bullet.x, target_y: bullet.y)
    return false if dist > 400 || dist < 20
    return false unless bullet.velocity_x && bullet.velocity_y

    bullet_angle = Math.atan2(bullet.velocity_y, bullet.velocity_x) * 180 / Math::PI
    angle_to_us = Math.atan2(y - bullet.y, x - bullet.x) * 180 / Math::PI
    angle_diff = normalize_angle(bullet_angle - angle_to_us).abs

    angle_diff < 25
  end

  def scan_opposite_corners
    corner = current_corner_to_scan
    corner_angle = angle_to(target_x: corner[:x], target_y: corner[:y])
    turret_diff = normalize_angle(corner_angle - turret_angle)

    return unless turret_diff.abs < 40

    scan(angle: 80, distance: 800, velocity: true)
  end

  def current_corner_to_scan
    corners = opposite_corners
    corners[(chronons / 25) % corners.size]
  end

  def opposite_corners
    case @wall
    when :bottom then [{ x: 60, y: arena_height - 60 }, { x: arena_width - 60, y: arena_height - 60 }]
    when :top    then [{ x: 60, y: 60 }, { x: arena_width - 60, y: 60 }]
    when :left   then [{ x: arena_width - 60, y: 60 }, { x: arena_width - 60, y: arena_height - 60 }]
    when :right  then [{ x: 60, y: 60 }, { x: 60, y: arena_height - 60 }]
    else [{ x: arena_width / 2, y: arena_height / 2 }]
    end
  end

  def target_in_corner?
    return false unless @target

    wall_x = [@target[:x], arena_width - @target[:x]].min
    wall_y = [@target[:y], arena_height - @target[:y]].min

    wall_x < CORNER_ZONE && wall_y < CORNER_ZONE
  end

  def safe_wall_from_corner
    return @wall unless @target

    left_half = @target[:x] < arena_width / 2
    bottom_half = @target[:y] < arena_height / 2

    if left_half && bottom_half
      y < arena_height / 2 ? :top : :right
    elsif !left_half && bottom_half
      y < arena_height / 2 ? :top : :left
    elsif left_half && !bottom_half
      y > arena_height / 2 ? :bottom : :right
    else
      y > arena_height / 2 ? :bottom : :left
    end
  end

  # ---------- Movement ----------

  def move
    if @evading.positive?
      evade
      @evading -= 1
      @plant_timer = 0
    elsif !on_current_wall?
      move_to_wall
    elsif lining_up_shot?
      plant_feet
    else
      @plant_timer = 0 if @plant_timer.positive?
      patrol_wall
    end
  end

  def evade
    if on_current_wall?
      evade_along_wall
    else
      evade_toward_wall
    end
  end

  def evade_along_wall
    if @evade_angle
      move_angle = @evade_angle
      @evade_angle = nil
    else
      # Micro-dodge: small slip perpendicular to wall
      move_angle = directed_wall_parallel_angle
      slip_offset = chronons % 4 < 2 ? 15 : -15
      move_angle = (move_angle + slip_offset) % 360
    end

    thrust(speed: 6, angle: move_angle) if speed < 10
    raise_shields(5) if energy > 50 && shield_level < 35
  end

  def evade_toward_wall
    base_angle = angle_to(target_x: wall_target_position[0], target_y: wall_target_position[1])
    jink_offset = chronons % 6 < 3 ? 25 : -25
    move_angle = (base_angle + jink_offset) % 360

    thrust(speed: 5, angle: move_angle) if speed < 10
    raise_shields(6) if energy > 45 && shield_level < 40
  end

  def move_to_wall
    move_angle = angle_to(target_x: wall_target_position[0], target_y: wall_target_position[1])
    thrust(speed: 4, angle: move_angle) if speed < 8
    raise_shields(5) if energy > 50 && shield_level < 40
  end

  def patrol_wall
    move_angle = directed_wall_parallel_angle
    move_angle = adjust_for_wall_distance(move_angle)

    thrust(speed: 2, angle: move_angle) if speed < 4
    raise_shields(3) if energy > 70 && shield_level < 20
  end

  def plant_feet
    @plant_timer += 1

    if @plant_timer > PLANT_DURATION
      @plant_timer = -PLANT_COOLDOWN
      return
    end

    brake if speed > 1.5
    raise_shields(4) if energy > 60 && shield_level < 30
  end

  def brake
    return unless velocity_angle  # stationary, no need to brake

    reverse_angle = (velocity_angle + 180) % 360
    thrust(speed: 1, angle: reverse_angle)
  end

  def on_current_wall?
    case @wall
    when :left   then x < WALL_DIST + 20
    when :right  then x > arena_width - WALL_DIST - 20
    when :bottom then y < WALL_DIST + 20
    when :top    then y > arena_height - WALL_DIST - 20
    else false
    end
  end

  def lining_up_shot?
    return false unless @target
    return false if energy < 50
    return false if @plant_timer.positive?

    target_angle = angle_to(target_x: @target[:x], target_y: @target[:y])
    turret_diff = normalize_angle(target_angle - turret_angle).abs
    turret_diff < 20
  end

  def wall_target_position
    case @wall
    when :left   then [WALL_DIST, y.clamp(100, arena_height - 100)]
    when :right  then [arena_width - WALL_DIST, y.clamp(100, arena_height - 100)]
    when :bottom then [x.clamp(100, arena_width - 100), WALL_DIST]
    when :top    then [x.clamp(100, arena_width - 100), arena_height - WALL_DIST]
    else [arena_width / 2, arena_height / 2]
    end
  end

  def adjust_for_wall_distance(angle)
    wall_dist = nearest_wall_distance

    if wall_dist < WALL_DIST - 15
      adjust_away_from_wall(angle, 20)
    elsif wall_dist > WALL_DIST + 25
      adjust_toward_wall(angle, 15)
    else
      angle
    end
  end

  # ---------- Combat ----------

  def aim_and_fire
    if @target
      aim_at_target
      attempt_shot
    else
      sweep_turret
    end
  end

  def aim_at_target
    target_angle = calculate_lead_angle
    turret_diff = normalize_angle(target_angle - turret_angle)
    rotate_turret(turret_diff.clamp(-15, 15))

    probe_target_health if turret_diff.abs < 20
  end

  def calculate_lead_angle
    if @target[:velocity_x] && @target[:velocity_y]
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
  end

  def probe_target_health
    return unless energy > 15 && (chronons % 10).zero?

    probe(:health, :shield)
    return unless probe_echo.found?

    @target[:health] = probe_echo.health
    @target[:shield] = probe_echo.shield_level
  end

  def attempt_shot
    return unless @target

    target_angle = angle_to(target_x: @target[:x], target_y: @target[:y])
    turret_diff = normalize_angle(target_angle - turret_angle).abs
    return unless turret_diff < 15

    dist = distance_to(target_x: @target[:x], target_y: @target[:y])
    return if dist > 600

    fire_appropriate_shot
  end

  def fire_appropriate_shot
    target_hp = (@target[:health] || 80) + (@target[:shield] || 0)
    energy_to_kill = (target_hp / 1.5).ceil

    if energy >= energy_to_kill && energy_to_kill <= 60
      fire(energy_to_kill)
    elsif energy > 50 && on_current_wall?
      fire(18)
    elsif energy > 70
      fire(15)
    end
  end

  def sweep_turret
    corner = current_corner_to_scan
    corner_angle = angle_to(target_x: corner[:x], target_y: corner[:y])
    turret_diff = normalize_angle(corner_angle - turret_angle)
    rotate_turret(turret_diff.clamp(-12, 12))
  end

  # ---------- Angle Helpers ----------

  def wall_parallel_angle
    case @wall
    when :bottom then 0
    when :top    then 180
    when :left   then 90
    when :right  then 270
    else 0
    end
  end

  def directed_wall_parallel_angle
    base = wall_parallel_angle
    @direction.positive? ? base : (base + 180) % 360
  end

  def random_wall_parallel_angle
    base = wall_parallel_angle
    rand > 0.5 ? base : (base + 180) % 360
  end

  def adjust_away_from_wall(angle, degrees)
    inward = case @wall
             when :bottom then 90
             when :top    then 270
             when :left   then 0
             when :right  then 180
             else 0
             end

    diff = normalize_angle(inward - angle)
    (angle + diff.clamp(-degrees, degrees)) % 360
  end

  def adjust_toward_wall(angle, degrees)
    outward = case @wall
              when :bottom then 270
              when :top    then 90
              when :left   then 180
              when :right  then 0
              else 0
              end

    diff = normalize_angle(outward - angle)
    (angle + diff.clamp(-degrees, degrees)) % 360
  end

  # Uses nearest_wall from Rubot module
  # Uses nearest_wall_distance from Rubot module
end
