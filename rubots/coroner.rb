# frozen_string_literal: true

# A defensive sniper that camps corners and takes precise shots.
# Flees to another corner if enemies get too close.
class Coroner
  include Rubowar::Rubot

  size :medium

  CORNER_BUFFER = 25
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
    @path = nil # Reset path for new destination
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
    # Find corner we can reach without moving toward the threat
    # Reject corners where the path crosses the threat direction
    threat_rad = direction * Math::PI / 180

    safe_corners = corners.reject do |c|
      corner_angle = angle_to(target_x: c[:x], target_y: c[:y])
      angle_diff = normalize_angle(corner_angle - direction).abs
      angle_diff < 60 # Reject if we'd have to move toward threat
    end

    # Pick closest safe corner, or farthest corner if no safe option
    if safe_corners.any?
      safe_corners.min_by { |c| distance_to(target_x: c[:x], target_y: c[:y]) }
    else
      corners.max_by { |c| distance_to(target_x: c[:x], target_y: c[:y]) }
    end
  end

  def check_for_danger
    # Only flee if already in a corner (scanning), not while moving
    return unless @mode == :scanning

    # SENSE: Pulse for nearby threats
    pulse(distance: DANGER_DISTANCE)
    return unless pulse_echo.any_rubots?

    # Something is too close - flee!
    closest = pulse_echo.closest_rubot(to_x: x, to_y: y)
    threat_angle = angle_to(target_x: closest.x, target_y: closest.y)
    @corner = corner_away_from(threat_angle)
    @path = nil # Reset path for new destination
    @mode = :fleeing
  end

  def move_to_corner_action
    move_along_wall_to(@corner, arrival_mode: :scanning, thrust_speed: 6)
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
        dist = distance_to(target_x:, target_y:)
        lead_time = dist / BULLET_SPEED
        target_x += @last_target[:velocity_x] * lead_time
        target_y += @last_target[:velocity_y] * lead_time
      end

      target_angle = angle_to(target_x:, target_y:)
      turret_diff = normalize_angle(target_angle - turret_angle)
      rotate_turret(turret_diff.clamp(-10, 10)) if turret_diff.abs > 3
    end

    # Fire on probe hit - bigger shot if flush with energy
    return unless probe_echo.found? && energy > 25

    shot = energy > 60 ? 25 : 15
    fire(shot)
  end

  def fleeing_action
    move_along_wall_to(@corner, arrival_mode: :scanning, thrust_speed: 7)
    raise_shields(5) if energy > 40 && shield_level < 30
  end

  def move_along_wall_to(destination, arrival_mode:, thrust_speed:)
    # Build path of waypoints along walls
    @path ||= build_wall_path(destination)

    # Get current target (first waypoint or final destination)
    current_target = @path.first || destination
    dist = distance_to(target_x: current_target[:x], target_y: current_target[:y])

    # Reached current waypoint, move to next
    if dist < CORNER_BUFFER && @path.any?
      @path.shift
      current_target = @path.first || destination
      dist = distance_to(target_x: current_target[:x], target_y: current_target[:y])
    end

    # Reached final destination
    if dist < CORNER_BUFFER / 2 && @path.empty?
      @mode = arrival_mode
      @path = nil
      return
    end

    # Move toward current target
    angle = angle_to(target_x: current_target[:x], target_y: current_target[:y])
    thrust(speed: thrust_speed, angle:) if speed < thrust_speed
  end

  def build_wall_path(destination)
    path = []

    # First, get to nearest wall if not already there
    wall_buffer = CORNER_BUFFER
    near_left = x < wall_buffer * 1.5
    near_right = x > arena_width - wall_buffer * 1.5
    near_bottom = y < wall_buffer * 1.5
    near_top = y > arena_height - wall_buffer * 1.5
    on_wall = near_left || near_right || near_bottom || near_top

    unless on_wall
      # Go to nearest wall first
      distances = {
        left: x,
        right: arena_width - x,
        bottom: y,
        top: arena_height - y
      }
      nearest = distances.min_by { |_, d| d }.first
      case nearest
      when :left then path << { x: wall_buffer, y: y }
      when :right then path << { x: arena_width - wall_buffer, y: y }
      when :bottom then path << { x: x, y: wall_buffer }
      when :top then path << { x: x, y: arena_height - wall_buffer }
      end
    end

    # Now figure out path along walls to destination
    # Determine which walls we need to travel along
    dest_on_left = destination[:x] < arena_width / 2
    dest_on_bottom = destination[:y] < arena_height / 2
    curr_on_left = (path.last || { x: x })[:x] < arena_width / 2
    curr_on_bottom = (path.last || { y: y })[:y] < arena_height / 2

    # If we need to change both x and y sides, add intermediate corner
    if curr_on_left != dest_on_left && curr_on_bottom != dest_on_bottom
      # Pick adjacent corner - prefer staying on current wall
      intermediate = if near_left || near_right || (!on_wall && [x, arena_width - x].min < [y, arena_height - y].min)
                       # On left/right wall, go vertical first
                       { x: curr_on_left ? wall_buffer : arena_width - wall_buffer,
                         y: dest_on_bottom ? wall_buffer : arena_height - wall_buffer }
                     else
                       # On top/bottom wall, go horizontal first
                       { x: dest_on_left ? wall_buffer : arena_width - wall_buffer,
                         y: curr_on_bottom ? wall_buffer : arena_height - wall_buffer }
                     end
      path << intermediate
    end

    path
  end

  def scan_distance
    @scan_distance ||= (arena_diagonal * 0.9).round.clamp(400, 1000)
  end
end
