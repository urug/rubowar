# frozen_string_literal: true

# A patient assassin that evades until it can deliver a killing blow.
# Cheap sensing (detect + pulse), saves energy, fires big when aligned.
class Evader
  include Rubowar::Rubot

  size :small # Agile, harder to hit, 8 energy regen

  PULSE_RANGE = 300       # Long range to find targets (6 energy)
  EVASION_CHRONONS = 12
  WALL_BUFFER = 80        # Large buffer for momentum
  MIN_SHOT_ENERGY = 10    # Don't bother with tiny shots
  ENERGON_RANGE = 150     # How far to go for energon

  def on_spawn
    @evading = 0
    @direction = rand > 0.5 ? 1 : -1
    @target = nil
    @juke_timer = 0
  end

  def act
    check_if_targeted

    # SENSE: Pulse every other chronon (6 energy)
    update_target if chronon.odd?

    move

    aim_at_target if @target

    # SENSE: Probe for health when turret is aligned
    probe_target_health if @target && turret_aligned?

    # COMBAT: Kill shot based on target's health
    attempt_kill_shot

    # queue detect_intel for targeted check
    detect
  end

  def on_hit(damage:, direction:)
    @evading = EVASION_CHRONONS
    @direction *= -1
  end

  def on_wall
    @direction *= -1
  end

  private

  def check_if_targeted
    # Proactive juking: change direction every 8-15 chronon when near enemy
    @juke_timer -= 1
    if @juke_timer <= 0 && @target
      dist = distance_to(target_x: @target[:x], target_y: @target[:y])
      if dist < 250 # In danger zone
        @direction *= -1
        @juke_timer = rand(8..15)
      end
    end

    return unless detect_intel.targeted?

    if detect_intel.probed.positive?
      # Being probed = enemy aiming at us, dodge NOW
      @evading = EVASION_CHRONONS
      @direction *= -1
      @juke_timer = rand(5..10)
    elsif detect_intel.scanned.positive?
      # Being scanned = enemy looking for us
      @evading = [8, @evading].max
      @direction *= -1 if rand < 0.5
    end
  end

  def update_target
    pulse(distance: PULSE_RANGE)
    return unless pulse_echo.any_rubots?

    closest = pulse_echo.closest_rubot(to_x: x, to_y: y)
    @target = { x: closest.x, y: closest.y }
  end

  def move
    # Priority: avoid walls first
    if wall_emergency?
      escape_wall
    elsif @evading.positive?
      evade
      @evading -= 1
    elsif @target
      keep_distance
    elsif collect_energon?
      collect_energon
    else
      drift_center
    end
  end

  def wall_emergency?
    # Emergency if close to wall with any momentum toward it
    (x < WALL_BUFFER && velocity_x.negative?) ||
      (x > arena_width - WALL_BUFFER && velocity_x.positive?) ||
      (y < WALL_BUFFER && velocity_y.negative?) ||
      (y > arena_height - WALL_BUFFER && velocity_y.positive?)
  end

  def escape_wall
    # Thrust toward center to brake
    center_angle = angle_to(target_x: arena_width / 2.0, target_y: arena_height / 2.0)
    thrust(speed: 3, angle: center_angle)
  end

  def evade
    base_angle = @target ? angle_to(target_x: @target[:x], target_y: @target[:y]) + 180 : rand(360)
    evade_angle = wall_adjust(base_angle + (60 * @direction))
    # Low speeds to avoid wall damage with momentum
    spd = approaching_wall? ? 2 : 4
    thrust(speed: spd, angle: evade_angle)
  end

  def keep_distance
    threat_angle = angle_to(target_x: @target[:x], target_y: @target[:y])
    move_angle = wall_adjust(threat_angle + (90 * @direction))
    spd = approaching_wall? ? 2 : 3
    thrust(speed: spd, angle: move_angle)
  end

  def near_wall?
    x < WALL_BUFFER || x > arena_width - WALL_BUFFER ||
      y < WALL_BUFFER || y > arena_height - WALL_BUFFER
  end

  def approaching_wall?
    # Check if momentum is carrying us toward a wall
    return true if x < WALL_BUFFER * 1.5 && velocity_x.negative?
    return true if x > arena_width - (WALL_BUFFER * 1.5) && velocity_x.positive?
    return true if y < WALL_BUFFER * 1.5 && velocity_y.negative?
    return true if y > arena_height - (WALL_BUFFER * 1.5) && velocity_y.positive?

    near_wall?
  end

  def collect_energon?
    return false if energy > 80 # Don't bother if already high

    @energon_target = find_nearest_energon(max_distance: ENERGON_RANGE)
    @energon_target != nil
  end

  def collect_energon
    angle = angle_to(target_x: @energon_target[:x], target_y: @energon_target[:y])
    spd = approaching_wall? ? 2 : 3
    thrust(speed: spd, angle: wall_adjust(angle))
    rotate_turret(6 * @direction) # Keep sweeping
  end

  def drift_center
    center_angle = angle_to(target_x: arena_width / 2.0, target_y: arena_height / 2.0)
    drift_angle = wall_adjust(center_angle + (45 * @direction))
    thrust(speed: 2, angle: drift_angle)
    rotate_turret(6 * @direction)
  end

  def aim_at_target
    target_angle = angle_to(target_x: @target[:x], target_y: @target[:y])
    diff = normalize_angle(target_angle - turret_angle)
    rotate_turret(diff.clamp(-20, 20))
  end

  def turret_aligned?
    return false unless @target

    target_angle = angle_to(target_x: @target[:x], target_y: @target[:y])
    normalize_angle(target_angle - turret_angle).abs < 15
  end

  def probe_target_health
    probe(:health, :shield)
    return unless probe_echo.found?

    @target[:health] = probe_echo.health
    @target[:shield] = probe_echo.shield_level
  end

  def attempt_kill_shot
    return unless @target && turret_aligned?

    # Calculate energy needed to kill (damage = energy * 1.5)
    target_hp = (@target[:health] || 80) + (@target[:shield] || 0)
    energy_to_kill = (target_hp / 1.5).ceil

    # Fire if we can kill or significantly wound (>50% of their HP)
    shot_energy = if energy >= energy_to_kill
                    energy_to_kill # Finish them
                  elsif energy >= (energy_to_kill * 0.5) && energy >= MIN_SHOT_ENERGY
                    energy # Significant damage
                  end

    fire(shot_energy) if shot_energy
  end

  def wall_adjust(angle)
    angle += 90 if x < WALL_BUFFER
    angle -= 90 if x > arena_width - WALL_BUFFER
    angle -= 90 if y < WALL_BUFFER
    angle += 90 if y > arena_height - WALL_BUFFER
    angle % 360
  end
end
