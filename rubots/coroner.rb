# frozen_string_literal: true

# A defensive sniper that camps corners and takes precise shots.
# Flees to another corner if enemies get too close.
class Coroner
  include Rubowar::Rubot

  size :medium

  CORNER_BUFFER = 60
  DANGER_DISTANCE = 150
  BULLET_SPEED = Rubowar::Config::Combat::BULLET_SPEED

  def on_spawn
    @mode = :moving_to_corner
    @corner = closest_corner
    @scan_direction = 1
    @last_target = nil
    @tracking = false
  end

  def act
    check_for_danger

    case @mode
    when :moving_to_corner
      move_to_corner_action
    when :scanning
      scanning_action
    when :fleeing
      fleeing_action
    end
  end

  def on_hit(damage:, direction:)
    # When hit, flee in the opposite direction
    @corner = corner_away_from(direction)
    @mode = :fleeing
  end

  def on_wall
    # If we hit a wall while fleeing, we're probably in a corner
    @mode = :scanning if @mode == :fleeing
  end

  private

  def corners
    @corners ||= [
      { x: CORNER_BUFFER, y: CORNER_BUFFER },                           # bottom-left
      { x: arena_width - CORNER_BUFFER, y: CORNER_BUFFER },             # bottom-right
      { x: CORNER_BUFFER, y: arena_height - CORNER_BUFFER },            # top-left
      { x: arena_width - CORNER_BUFFER, y: arena_height - CORNER_BUFFER } # top-right
    ]
  end

  def closest_corner
    corners.min_by { |c| distance_to(target_x: c[:x], target_y: c[:y]) }
  end

  def farthest_corner
    corners.max_by { |c| distance_to(target_x: c[:x], target_y: c[:y]) }
  end

  def corner_away_from(direction)
    # Find corner that's most opposite to the threat direction
    threat_x = x + (Math.cos(direction * Math::PI / 180) * 100)
    threat_y = y + (Math.sin(direction * Math::PI / 180) * 100)
    corners.max_by { |c| Math.sqrt(((c[:x] - threat_x)**2) + ((c[:y] - threat_y)**2)) }
  end

  def check_for_danger
    return if @mode == :fleeing

    # SENSE: Pulse for nearby threats
    pulse(distance: DANGER_DISTANCE)
    return unless pulse_echo.any_rubots?

    # Something is too close - flee!
    closest = pulse_echo.closest_rubot(to_x: x, to_y: y)
    threat_angle = angle_to(target_x: closest.x, target_y: closest.y)
    @corner = corner_away_from(threat_angle)
    @mode = :fleeing
  end

  def move_to_corner_action
    dist = distance_to(target_x: @corner[:x], target_y: @corner[:y])

    if dist < CORNER_BUFFER / 2
      @mode = :scanning
      return
    end

    angle = angle_to(target_x: @corner[:x], target_y: @corner[:y])
    thrust(speed: 5, angle:) if speed < 5
  end

  def scanning_action
    if @tracking
      tracking_action
    else
      sweeping_action
    end

    # Build shields while camping
    raise_shields(3) if energy > 70 && shield_level < 25
  end

  def sweeping_action
    # SENSE: Scan for targets
    scan(angle: 70, distance: scan_distance) if energy > 20

    if scan_echo.any_rubots?
      closest = scan_echo.closest_rubot(to_x: x, to_y: y)
      @last_target = { x: closest.x, y: closest.y, velocity_x: closest.velocity_x, velocity_y: closest.velocity_y }
      @tracking = true
      @chronons_without_probe_hit = 0
    end

    # Sweep turret toward center
    center_angle = angle_to(target_x: arena_width / 2.0, target_y: arena_height / 2.0)
    turret_offset = normalize_angle(turret_angle - center_angle)

    if turret_offset.abs > 100
      rotate_turret(turret_offset.positive? ? -15 : 15)
    else
      if turret_offset > 80 && @scan_direction.positive?
        @scan_direction = -1
      elsif turret_offset < -80 && @scan_direction.negative?
        @scan_direction = 1
      end
      rotate_turret(6 * @scan_direction)
    end
  end

  def tracking_action
    # SENSE: Probe for position/velocity (7 energy)
    probe(:position, :velocity) if energy > 20

    if probe_echo.found?
      @last_target = { x: probe_echo.x, y: probe_echo.y,
                       velocity_x: probe_echo.velocity_x, velocity_y: probe_echo.velocity_y }
      @chronons_without_probe_hit = 0
    else
      @chronons_without_probe_hit = (@chronons_without_probe_hit || 0) + 1
      if @chronons_without_probe_hit > 20
        @tracking = false
        return
      end
    end

    # Aim with lead prediction
    if @last_target
      target_x = @last_target[:x]
      target_y = @last_target[:y]

      if @last_target[:velocity_x] && @last_target[:velocity_y]
        dist = distance_to(target_x: target_x, target_y: target_y)
        lead_time = dist / BULLET_SPEED
        target_x += @last_target[:velocity_x] * lead_time
        target_y += @last_target[:velocity_y] * lead_time
      end

      target_angle = angle_to(target_x: target_x, target_y: target_y)
      turret_diff = normalize_angle(target_angle - turret_angle)
      rotate_turret(turret_diff.clamp(-10, 10)) if turret_diff.abs > 3
    end

    # Fire on probe hit - bigger shot if flush with energy
    return unless probe_echo.found? && energy > 25

    shot = energy > 60 ? 25 : 15
    fire(shot)
  end

  def fleeing_action
    dist = distance_to(target_x: @corner[:x], target_y: @corner[:y])

    if dist < CORNER_BUFFER / 2
      @mode = :scanning
      return
    end

    # MOVE: Run to corner
    angle = angle_to(target_x: @corner[:x], target_y: @corner[:y])
    thrust(speed: 6, angle:) if speed < 6

    # COMBAT: Build shields while fleeing
    raise_shields(5) if energy > 40 && shield_level < 30
  end

  def scan_distance
    @scan_distance ||= (arena_diagonal * 0.6).round.clamp(300, 700)
  end
end
