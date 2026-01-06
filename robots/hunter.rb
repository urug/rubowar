# frozen_string_literal: true

# A rubot that patrols the arena looking for targets, then chases them down.
# Uses pulse for wide-area detection and scan for precision targeting.
# Small size for better mobility and survivability.
class Hunter
  include Rubowar::Rubot

  size :small # Small = faster, harder to hit, cheaper movement

  WALL_BUFFER = 80
  PULSE_DISTANCE = 300
  SCAN_ANGLE = 70
  SCAN_ANGLE_WIDE = 100  # Used when losing target
  SCAN_DISTANCE = 350
  PATROL_SPEED = 5
  CHASE_SPEED = 7
  BULLET_SPEED = 15 # Approximate bullet speed for lead calculation
  GIVE_UP_TICKS = 50  # More persistence before reverting to patrol
  ENERGON_COLLECT_RANGE = 250

  def on_spawn
    @mode = :patrol
    @target_x = nil  # Lead-adjusted for shooting
    @target_y = nil
    @target_base_x = nil  # Raw position for movement
    @target_base_y = nil
    @target_vx = nil
    @target_vy = nil
    @target_health = nil  # Track target health for "finish them" logic
    @patrol_angle = rand(360)
    @ticks_without_target = 0
    @pulse_cooldown = 0
    @dodge_direction = 1  # Alternate dodge direction for on_hit
    @probe_cooldown = 0
    @target_energon = nil
  end

  def tick
    case @mode
    when :patrol
      patrol_tick
    when :chase
      chase_tick
    when :collecting
      collecting_tick
    end
  end

  def on_hit(_damage, direction)
    # Reactive dodge - move perpendicular to incoming fire
    @dodge_direction *= -1
    dodge_angle = direction + (90 * @dodge_direction)
    thrust(speed: CHASE_SPEED, angle: dodge_angle)

    # Boost shields when under fire
    shield(6) if energy > 25 && shield_level < 40

    # If not already chasing, acquire attacker's direction
    return unless @mode == :patrol

    # Estimate attacker position based on bullet direction
    attacker_angle = (direction + 180) % 360
    estimated_dist = 200
    @target_base_x = x + Math.cos(attacker_angle * Math::PI / 180) * estimated_dist
    @target_base_y = y + Math.sin(attacker_angle * Math::PI / 180) * estimated_dist
    @target_x = @target_base_x
    @target_y = @target_base_y
    @mode = :chase
    @ticks_without_target = 0
  end

  def on_wall
    @patrol_angle = (@patrol_angle + 120 + rand(60)) % 360
  end

  def on_energon(_amount)
    @target_energon = nil
    @mode = :patrol
  end

  private

  def patrol_tick
    # SENSE: Pulse periodically to find targets
    @pulse_cooldown -= 1 if @pulse_cooldown > 0
    if @pulse_cooldown <= 0
      pulse(distance: PULSE_DISTANCE)
      @pulse_cooldown = 3

      # Process previous pulse results
      if pulse_result
        rubots = pulse_result.select { |t| t[:type] == :rubot }
        if rubots.any?
          closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
          acquire_target(closest[:x], closest[:y])
          return
        end
      end
    end

    # Check for energons when no combat target
    if energy < 80
      energon = find_best_energon
      if energon
        @target_energon = energon
        @mode = :collecting
        return collecting_tick
      end
    end

    # MOVE: Patrol and rotate turret
    avoid_walls
    turret(8)
    thrust(speed: PATROL_SPEED, angle: @patrol_angle) if speed < PATROL_SPEED
  end

  def chase_tick
    return revert_to_patrol if @target_x.nil?

    # === SENSE PHASE ===
    current_scan_angle = @ticks_without_target > 5 ? SCAN_ANGLE_WIDE : SCAN_ANGLE

    # Queue scan for next tick
    scan(angle: current_scan_angle, distance: SCAN_DISTANCE, velocity: true)

    # Process previous scan results
    if scan_result
      rubots = scan_result.select { |t| t[:type] == :rubot }
      if rubots.any?
        closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
        update_target_with_lead(closest)
        @ticks_without_target = 0
      else
        @ticks_without_target += 1
      end
    else
      @ticks_without_target += 1
    end

    # Try wider pulse when losing target
    if @ticks_without_target > 10 && @ticks_without_target % 5 == 0
      pulse(distance: PULSE_DISTANCE + 100)
      if pulse_result
        rubots = pulse_result.select { |t| t[:type] == :rubot }
        if rubots.any?
          closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
          @target_base_x = closest[:x]
          @target_base_y = closest[:y]
          @target_x = closest[:x]
          @target_y = closest[:y]
          @target_vx = closest[:velocity_x]
          @target_vy = closest[:velocity_y]
          @target_health = nil
          @ticks_without_target = 5
        end
      end
    end

    return revert_to_patrol if @ticks_without_target > GIVE_UP_TICKS

    # Probe for health when aligned
    target_angle = angle_to(@target_x, @target_y)
    turret_diff = normalize_angle(target_angle - turret_angle)

    @probe_cooldown -= 1 if @probe_cooldown > 0
    if @probe_cooldown <= 0 && turret_diff.abs < 15 && energy > 15
      probe(:position, :velocity, :health)
      @probe_cooldown = 8
      if probe_result&.any?
        update_target_with_lead(probe_result)
        @target_health = probe_result[:health]
        @ticks_without_target = 0
      end
    end

    # === MOVE PHASE ===
    turret(turret_diff.clamp(-25, 25))

    base_x = @target_base_x || @target_x
    base_y = @target_base_y || @target_y
    dist = distance_to(base_x, base_y)

    target_speed = (@target_vx && @target_vy) ? Math.sqrt(@target_vx**2 + @target_vy**2) : 0

    move_angle = if target_speed < 2
                   angle_to(base_x, base_y)
                 elsif dist > 180
                   calculate_intercept_angle
                 else
                   angle_to(base_x, base_y)
                 end

    move_speed = (target_speed < 2 && dist > 100) ? 6 : CHASE_SPEED
    thrust(speed: move_speed, angle: move_angle)

    # === COMBAT PHASE ===
    if turret_diff.abs < 30
      target_weak = @target_health && @target_health < 40
      fire_power = if (dist < 80 && turret_diff.abs < 10) || target_weak
                     15
                   elsif dist < 120 && turret_diff.abs < 12
                     12
                   else
                     8
                   end
      min_energy = target_weak ? 15 : 20
      fire(fire_power) if energy > min_energy
    end

    shield(5) if energy > 35 && shield_level < 25
  end

  def update_target_with_lead(target_data)
    # Store raw position for movement
    @target_base_x = target_data[:x]
    @target_base_y = target_data[:y]

    # Store velocity for intercept calculation
    @target_vx = target_data[:velocity_x]
    @target_vy = target_data[:velocity_y]

    if @target_vx && @target_vy
      # Calculate lead based on distance and bullet speed
      dist = distance_to(@target_base_x, @target_base_y)
      time_to_target = dist / BULLET_SPEED
      lead_ticks = [time_to_target, 15].min # Cap lead at 15 ticks

      @target_x = @target_base_x + @target_vx * lead_ticks
      @target_y = @target_base_y + @target_vy * lead_ticks
    else
      @target_x = @target_base_x
      @target_y = @target_base_y
    end
  end

  def calculate_intercept_angle
    # Use base position for movement calculations
    base_x = @target_base_x || @target_x
    base_y = @target_base_y || @target_y

    return angle_to(base_x, base_y) unless @target_vx && @target_vy

    # Calculate target speed
    target_speed = Math.sqrt(@target_vx**2 + @target_vy**2)
    return angle_to(base_x, base_y) if target_speed < 1

    # Calculate intercept point - where target will be when we arrive
    dist = distance_to(base_x, base_y)
    time_to_intercept = dist / CHASE_SPEED

    # Predict where target will be
    intercept_x = base_x + @target_vx * time_to_intercept * 0.7
    intercept_y = base_y + @target_vy * time_to_intercept * 0.7

    # Clamp to arena bounds
    intercept_x = intercept_x.clamp(30, arena_width - 30)
    intercept_y = intercept_y.clamp(30, arena_height - 30)

    angle_to(intercept_x, intercept_y)
  end

  def acquire_target(target_x, target_y)
    @mode = :chase
    @target_base_x = target_x
    @target_base_y = target_y
    @target_x = target_x
    @target_y = target_y
    @target_vx = nil
    @target_vy = nil
    @ticks_without_target = 0

    # Turn turret toward target
    target_angle = angle_to(target_x, target_y)
    turret_diff = normalize_angle(target_angle - turret_angle)
    turret(turret_diff.clamp(-25, 25))
  end

  def revert_to_patrol
    @mode = :patrol
    @target_x = nil
    @target_y = nil
    @target_base_x = nil
    @target_base_y = nil
    @target_vx = nil
    @target_vy = nil
    @target_health = nil
    @ticks_without_target = 0
    @pulse_cooldown = 0
    @probe_cooldown = 0
  end

  def avoid_walls
    if x < WALL_BUFFER
      @patrol_angle = rand(60) - 30 # Roughly east
    elsif x > arena_width - WALL_BUFFER
      @patrol_angle = 180 + rand(60) - 30 # Roughly west
    elsif y < WALL_BUFFER
      @patrol_angle = 90 + rand(60) - 30 # Roughly north
    elsif y > arena_height - WALL_BUFFER
      @patrol_angle = 270 + rand(60) - 30 # Roughly south
    end
  end

  def distance_to(target_x, target_y)
    Math.sqrt((target_x - x)**2 + (target_y - y)**2)
  end

  def angle_to(target_x, target_y)
    Math.atan2(target_y - y, target_x - x) * 180 / Math::PI
  end

  def normalize_angle(angle)
    angle = angle % 360
    angle -= 360 if angle > 180
    angle += 360 if angle < -180
    angle
  end

  def collecting_tick
    # Pulse to check for enemies while collecting
    @pulse_cooldown -= 1 if @pulse_cooldown > 0
    if @pulse_cooldown <= 0
      pulse(distance: PULSE_DISTANCE)
      @pulse_cooldown = 3

      if pulse_result
        rubots = pulse_result.select { |t| t[:type] == :rubot }
        if rubots.any?
          closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
          @target_energon = nil
          acquire_target(closest[:x], closest[:y])
          return
        end
      end
    end

    # Check if energon still exists
    unless energon_still_exists?(@target_energon)
      @target_energon = nil
      @mode = :patrol
      return
    end

    # Move toward energon
    energon_angle = angle_to(@target_energon[:x], @target_energon[:y])
    energon_dist = distance_to(@target_energon[:x], @target_energon[:y])
    collect_speed = energon_dist < 50 ? PATROL_SPEED : CHASE_SPEED

    thrust(speed: collect_speed, angle: energon_angle)
    turret(8)
  end

  def find_best_energon
    return nil if energons.empty?

    nearby = energons.select { |e| distance_to(e[:x], e[:y]) < ENERGON_COLLECT_RANGE }
    return nil if nearby.empty?

    nearby.min_by { |e| distance_to(e[:x], e[:y]) }
  end

  def energon_still_exists?(target)
    return false unless target

    energons.any? { |e| e[:x] == target[:x] && e[:y] == target[:y] }
  end
end
