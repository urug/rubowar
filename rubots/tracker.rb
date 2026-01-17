# frozen_string_literal: true

# A stationary turret that uses SimpleTargeting to track and shoot enemies.
# Large size provides 120 HP and 18 energy regen - tanky and high firepower.
# A step up from Spinner - demonstrates proper target tracking.
class Tracker
  include Rubowar::Rubot
  include Rubowar::SimpleTargeting

  size :large

  def on_spawn
    @last_pulse = -100
  end

  def act
    sense_targets
    track_turret

    if target
      fire(14) if turret_aligned?(target) && energy > 25
    else
      # No target - spin turret while searching
      rotate_turret(10)
    end

    raise_shields(6) if energy > 50 && shield_level < 40
  end

  private

  def sense_targets
    # Pulse frequently for position updates (omnidirectional - always works)
    if chronon - @last_pulse >= 8
      pulse(distance: arena_diagonal * 0.6)
      @last_pulse = chronon

      if pulse_echo.any_rubots?
        closest = pulse_echo.closest_rubot(to_x: x, to_y: y)
        # Update position from pulse, preserve velocity if we have it
        self.target = {
          x: closest.x,
          y: closest.y,
          velocity_x: target&.dig(:velocity_x),
          velocity_y: target&.dig(:velocity_y)
        }
      else
        # Lost target
        self.target = nil
      end
    end

    # Scan for velocity data when turret is roughly aligned
    return unless target && energy > 10

    target_angle = angle_to(target_x: target[:x], target_y: target[:y])
    turret_diff = normalize_angle(target_angle - turret_angle).abs

    # Only scan if turret is within 45° of target (scan is 90° arc)
    return unless turret_diff < 45

    scan(angle: 90, distance: 400, velocity: true)
    return unless scan_echo.any_rubots?

    closest = scan_echo.closest_rubot(to_x: x, to_y: y)
    self.target = {
      x: closest.x,
      y: closest.y,
      velocity_x: closest.velocity_x,
      velocity_y: closest.velocity_y
    }
  end

  def track_turret
    return unless target

    # Use SimpleTargeting's lead calculation
    rotate_turret(aim_at_target(target))
  end
end
