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

  def tick
    check_for_danger

    case @mode
    when :moving_to_corner
      move_to_corner_tick
    when :scanning
      scanning_tick
    when :fleeing
      fleeing_tick
    end
  end

  def on_hit(_damage, direction)
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
    corners.min_by { |c| distance_to(c[:x], c[:y]) }
  end

  def farthest_corner
    corners.max_by { |c| distance_to(c[:x], c[:y]) }
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
    return unless pulse_result

    rubots = pulse_result.select { |t| t[:type] == :rubot }
    return if rubots.empty?

    # Something is too close - flee!
    closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
    threat_angle = angle_to(closest[:x], closest[:y])
    @corner = corner_away_from(threat_angle)
    @mode = :fleeing
  end

  def move_to_corner_tick
    dist = distance_to(@corner[:x], @corner[:y])

    if dist < CORNER_BUFFER / 2
      @mode = :scanning
      return
    end

    angle = angle_to(@corner[:x], @corner[:y])
    thrust(speed: 5, angle:) if speed < 5
  end

  def scanning_tick
    if @tracking
      tracking_tick
    else
      sweeping_tick
    end

    # Build shields while camping
    shield(3) if energy > 70 && shield_level < 25
  end

  def sweeping_tick
    # SENSE: Scan for targets
    scan(angle: 70, distance: scan_distance) if energy > 20

    if scan_result
      rubots = scan_result.select { |t| t[:type] == :rubot }
      if rubots.any?
        closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
        @last_target = closest
        @last_target_tick = tick_number
        @tracking = true
        @ticks_without_probe_hit = 0
      end
    end

    # Sweep turret toward center
    center_angle = angle_to(arena_width / 2.0, arena_height / 2.0)
    turret_offset = normalize_angle(turret_angle - center_angle)

    if turret_offset.abs > 100
      turret(turret_offset.positive? ? -15 : 15)
    else
      if turret_offset > 80 && @scan_direction.positive?
        @scan_direction = -1
      elsif turret_offset < -80 && @scan_direction.negative?
        @scan_direction = 1
      end
      turret(6 * @scan_direction)
    end
  end

  def tracking_tick
    # SENSE: Probe for position/velocity (7 energy)
    probe(:position, :velocity) if energy > 20

    if probe_result&.any?
      @last_target = probe_result
      @last_target_tick = tick_number
      @ticks_without_probe_hit = 0
    else
      @ticks_without_probe_hit = (@ticks_without_probe_hit || 0) + 1
      if @ticks_without_probe_hit > 20
        @tracking = false
        return
      end
    end

    # Aim with lead prediction
    if @last_target
      target_x = @last_target[:x]
      target_y = @last_target[:y]

      if @last_target[:velocity_x] && @last_target[:velocity_y]
        dist = distance_to(target_x, target_y)
        lead_time = dist / BULLET_SPEED
        target_x += @last_target[:velocity_x] * lead_time
        target_y += @last_target[:velocity_y] * lead_time
      end

      target_angle = angle_to(target_x, target_y)
      turret_diff = normalize_angle(target_angle - turret_angle)
      turret(turret_diff.clamp(-10, 10)) if turret_diff.abs > 3
    end

    # Fire on probe hit - bigger shot if flush with energy
    if probe_result&.any? && energy > 25
      shot = energy > 60 ? 25 : 15
      fire(shot)
    end
  end

  def fleeing_tick
    dist = distance_to(@corner[:x], @corner[:y])

    if dist < CORNER_BUFFER / 2
      @mode = :scanning
      return
    end

    # MOVE: Run to corner
    angle = angle_to(@corner[:x], @corner[:y])
    thrust(speed: 6, angle:) if speed < 6

    # COMBAT: Build shields while fleeing
    shield(5) if energy > 40 && shield_level < 30
  end

  def scan_distance
    @scan_distance ||= (arena_diagonal * 0.6).round.clamp(300, 700)
  end
end
