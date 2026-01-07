# frozen_string_literal: true

# A pure ramming tank. No bullets - just finds targets and runs them down.
# Builds shields and accelerates as it closes distance for maximum impact.
class Crusher
  include Rubowar::Rubot

  size :large # Large = more collision damage, more HP (120)

  ENERGON_COLLECT_RANGE = 300

  def on_spawn
    @target = nil
    @last_pulse_tick = -100
    @target_energon = nil
  end

  def tick
    find_target if @target.nil? || tick_number - @last_pulse_tick > 25

    if @target
      @target_energon = nil
      chase_and_ram
    elsif @target_energon
      collecting_tick
    else
      wander
    end
  end

  def on_hit(_damage, direction)
    # Attacker is behind us - turn and chase
    attacker_angle = (direction + 180) % 360
    @target = {
      x: x + (Math.cos(attacker_angle * Math::PI / 180) * 100),
      y: y + (Math.sin(attacker_angle * Math::PI / 180) * 100)
    }
  end

  def on_collision(_other)
    # Successful ram! Find new target
    @target = nil
  end

  def on_energon(_amount)
    @target_energon = nil
  end

  private

  def find_target
    return unless energy > 20

    # SENSE: Queue new pulse for next tick
    pulse(distance: 400)
    @last_pulse_tick = tick_number

    # Process previous pulse results
    return unless pulse_result

    rubots = pulse_result.select { |t| t[:type] == :rubot }
    @target = rubots.min_by { |t| distance_to(t[:x], t[:y]) } unless rubots.empty?
  end

  def chase_and_ram
    # Calculate target position with lead prediction
    target_x = @target[:x]
    target_y = @target[:y]

    if @target[:velocity_x] && @target[:velocity_y]
      dist = distance_to(target_x, target_y)
      lead_ticks = (dist / 10.0).clamp(1, 25)
      target_x += @target[:velocity_x] * lead_ticks
      target_y += @target[:velocity_y] * lead_ticks
    end

    target_x = target_x.clamp(25, arena_width - 25)
    target_y = target_y.clamp(25, arena_height - 25)

    chase_angle = angle_to(target_x, target_y)
    dist = distance_to(target_x, target_y)
    turret_diff = normalize_angle(chase_angle - turret_angle)

    # SENSE: Queue probe when turret is aligned
    if turret_diff.abs < 10 && energy > 12
      probe(:position, :velocity)
      # Process previous probe result
      @target = probe_result if probe_result&.any?
    end

    # MOVE: Point turret at target and chase
    turret(turret_diff.clamp(-15, 15))

    # Speed scales with distance - more aggressive as we close in
    chase_speed = if dist < 80 then 8
                  elsif dist < 150 then 7
                  elsif dist < 250 then 6
                  else 5
                  end
    thrust(speed: chase_speed, angle: chase_angle)

    # COMBAT: Shields scale with distance
    if dist < 80
      shield(8) if energy > 15 && shield_level < 80
    elsif dist < 150
      shield(6) if energy > 20 && shield_level < 60
    elsif dist < 250
      shield(4) if energy > 25 && shield_level < 40
    elsif energy > 30 && shield_level < 30
      shield(3)
    end
  end

  def wander
    # Check for energons while wandering
    if energy < 80
      energon = find_nearest_energon(max_distance: ENERGON_COLLECT_RANGE)
      if energon
        @target_energon = energon
        return collecting_tick
      end
    end

    center_x = arena_width / 2.0
    center_y = arena_height / 2.0
    angle = angle_to(center_x, center_y)

    # MOVE: Head toward center, spin turret
    turret(10)
    thrust(speed: 4, angle:)

    # COMBAT: Light shields
    shield(3) if energy > 40 && shield_level < 30
  end

  def collecting_tick
    # Check if energon still exists
    unless energon_still_exists?(@target_energon)
      @target_energon = nil
      return
    end

    # Move toward energon
    energon_angle = angle_to(@target_energon[:x], @target_energon[:y])
    energon_dist = distance_to(@target_energon[:x], @target_energon[:y])
    collect_speed = energon_dist < 50 ? 4 : 6

    thrust(speed: collect_speed, angle: energon_angle)
    turret(10)

    # Light shields while collecting
    shield(3) if energy > 40 && shield_level < 30
  end
end
