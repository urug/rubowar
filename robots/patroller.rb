# frozen_string_literal: true

# A rubot that patrols the perimeter using all sensing methods.
# Uses pulse for broad awareness, scan for directional search, probe for tracking.
class Patroller
  include Rubowar::Rubot

  size :small

  WALL_DISTANCE = 50
  CORNER_DISTANCE = 80
  SPEED_SLOW = 4
  SPEED_FAST = 6
  BULLET_SPEED = Rubowar::Config::Combat::BULLET_SPEED
  PULSE_RANGE = 500 # Must cover most of arena to find corner campers
  SCAN_RANGE = 400
  ENERGON_WALL_PROXIMITY = 120 # Only collect energons this close to our wall

  def on_spawn
    @clockwise = true
    @on_perimeter = false
    @speed_phase = 0
    @target = nil
    @tracking_ticks = 0
    @sense_tick = 0
    @target_energon = nil
  end

  def tick
    # SENSE: Process results and queue new sensing
    process_sensing
    queue_sensing

    if @on_perimeter
      patrol_perimeter
    else
      move_to_wall
    end
  end

  def on_hit(_damage, direction)
    @clockwise = !@clockwise
    thrust(speed: SPEED_FAST, angle: direction + (@clockwise ? 90 : -90))
    shield(3) if energy > 40 && shield_level < 20
  end

  def on_wall
    @on_perimeter = true
  end

  def on_energon(_amount)
    @target_energon = nil
  end

  private

  # === SENSING ===

  def process_sensing
    # Process pulse results - finds targets anywhere in range
    if pulse_result
      rubots = pulse_result.select { |t| t[:type] == :rubot }
      if rubots.any?
        closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
        acquire_or_update_target(closest)
      end
    end

    # Process scan results - directional search with velocity
    if scan_result
      rubots = scan_result.select { |t| t[:type] == :rubot }
      if rubots.any?
        closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
        acquire_or_update_target(closest)
      end
    end

    # Process probe results - precise tracking
    acquire_or_update_target(probe_result) if probe_result&.any?

    # Age out stale target
    return unless @target

    @tracking_ticks += 1
    @target = nil if @tracking_ticks > 25
  end

  def acquire_or_update_target(data)
    @target = {
      x: data[:x],
      y: data[:y],
      velocity_x: data[:velocity_x],
      velocity_y: data[:velocity_y]
    }
    @tracking_ticks = 0
  end

  def queue_sensing
    @sense_tick += 1

    if @target
      # Have a target - probe every 4 ticks to save energy (probe costs 7)
      probe(:position, :velocity) if turret_aligned? && energy > 25 && (@sense_tick % 4).zero?
    elsif (@sense_tick % 8).zero? && energy > 20
      # No target - pulse every 8 ticks (costs 7 energy)
      # Skip expensive scans - pulse finds everyone
      pulse(distance: PULSE_RANGE)
    end
  end

  def turret_aligned?
    return false unless @target

    target_angle = calculate_lead_angle
    turret_diff = normalize_angle(target_angle - turret_angle).abs
    turret_diff < 20
  end

  # === MOVEMENT ===

  def move_to_wall
    dist_left = x
    dist_right = arena_width - x
    dist_bottom = y
    dist_top = arena_height - y
    min_dist = [dist_left, dist_right, dist_bottom, dist_top].min

    if min_dist < WALL_DISTANCE + 10
      @on_perimeter = true
      return
    end

    angle = if min_dist == dist_left then 180
            elsif min_dist == dist_right then 0
            elsif min_dist == dist_bottom then 270
            else 90
            end

    # MOVE: Head to wall, aim turret
    thrust(speed: SPEED_FAST, angle:)
    aim_turret

    # COMBAT: Fire if aligned
    fire_at_target
  end

  def patrol_perimeter
    # Reverse at corners
    @clockwise = !@clockwise if near_any_corner?

    # Check for energons near our wall (only if no combat target and low-ish energy)
    if !@target && energy < 70
      energon = find_energon_on_my_wall
      @target_energon = energon if energon
    end

    # Clear energon target if it's gone
    @target_energon = nil if @target_energon && !energon_still_exists?(@target_energon)

    # MOVE: Patrol with oscillating speed, or collect energon
    @speed_phase = (@speed_phase + 1) % 20
    current_speed = @speed_phase < 10 ? SPEED_SLOW : SPEED_FAST

    if @target_energon && !@target
      # Detour to collect energon
      energon_angle = angle_to(@target_energon[:x], @target_energon[:y])
      thrust(speed: SPEED_FAST, angle: energon_angle)
    else
      update_patrol_angle
      thrust(speed: current_speed, angle: @patrol_angle)
    end

    aim_turret

    # COMBAT: Fire and shield
    fire_at_target
    shield(2) if energy > 50 && shield_level < 15
  end

  def aim_turret
    if @target
      target_angle = calculate_lead_angle
      turret_diff = normalize_angle(target_angle - turret_angle)
      turret(turret_diff.clamp(-20, 20))
    else
      # Sweep turret inward to scan arena interior
      inward_angle = angle_to(arena_width / 2, arena_height / 2)
      turret_diff = normalize_angle(inward_angle - turret_angle)
      turret(turret_diff.clamp(-10, 10))
    end
  end

  # === COMBAT ===

  def fire_at_target
    return unless @target && energy > 12

    target_angle = calculate_lead_angle
    turret_diff = normalize_angle(target_angle - turret_angle).abs
    dist = distance_to(@target[:x], @target[:y])

    if turret_diff < 12
      power = dist < 120 ? 10 : 8
      fire(power)
    elsif turret_diff < 25
      fire(6)
    end
  end

  def calculate_lead_angle
    return angle_to(@target[:x], @target[:y]) unless @target[:velocity_x] && @target[:velocity_y]

    dist = distance_to(@target[:x], @target[:y])
    time_to_target = dist / BULLET_SPEED
    lead_ticks = [time_to_target, 10].min

    lead_x = @target[:x] + (@target[:velocity_x] * lead_ticks)
    lead_y = @target[:y] + (@target[:velocity_y] * lead_ticks)

    lead_x = lead_x.clamp(20, arena_width - 20)
    lead_y = lead_y.clamp(20, arena_height - 20)

    angle_to(lead_x, lead_y)
  end

  # === HELPERS ===

  def near_any_corner?
    corners = [
      [CORNER_DISTANCE, CORNER_DISTANCE],
      [arena_width - CORNER_DISTANCE, CORNER_DISTANCE],
      [CORNER_DISTANCE, arena_height - CORNER_DISTANCE],
      [arena_width - CORNER_DISTANCE, arena_height - CORNER_DISTANCE]
    ]
    corners.any? { |cx, cy| distance_to(cx, cy) < CORNER_DISTANCE }
  end

  def nearest_wall
    dist_left = x
    dist_right = arena_width - x
    dist_bottom = y
    dist_top = arena_height - y
    min_dist = [dist_left, dist_right, dist_bottom, dist_top].min

    if min_dist == dist_bottom then :bottom
    elsif min_dist == dist_right then :right
    elsif min_dist == dist_top then :top
    else :left
    end
  end

  def update_patrol_angle
    @patrol_angle = case nearest_wall
                    when :bottom then @clockwise ? 0 : 180
                    when :right then @clockwise ? 90 : 270
                    when :top then @clockwise ? 180 : 0
                    when :left then @clockwise ? 270 : 90
                    end
  end

  def find_energon_on_my_wall
    return nil if energons.empty?

    wall = nearest_wall
    nearby = energons.select do |e|
      # Check if energon is near the same wall we're patrolling
      near_same_wall = case wall
                       when :bottom then e[:y] < ENERGON_WALL_PROXIMITY
                       when :top then e[:y] > arena_height - ENERGON_WALL_PROXIMITY
                       when :left then e[:x] < ENERGON_WALL_PROXIMITY
                       when :right then e[:x] > arena_width - ENERGON_WALL_PROXIMITY
                       end
      near_same_wall && distance_to(e[:x], e[:y]) < 200
    end

    return nil if nearby.empty?

    nearby.min_by { |e| distance_to(e[:x], e[:y]) }
  end
end
