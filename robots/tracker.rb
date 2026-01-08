# frozen_string_literal: true

# A stationary turret that uses SimpleTargeting to track and shoot enemies.
# Large size provides 120 HP and 12 energy regen - tanky and high firepower.
class Tracker
  include Rubowar::Rubot
  include Rubowar::SimpleTargeting

  size :large

  def act
    # Try sensors in order: probe (precise) → scan (arc) → pulse (360°)
    self.target =
      acquire_target_from_probe(probe_result) ||
      acquire_target_from_scan(scan_result) ||
      acquire_target_from_pulse(pulse_result)

    if target
      turret(aim_at_target(target))
      fire(12) if turret_aligned?(target) && energy > 25
      probe(:position, :velocity)
      @tracked_target = target
    elsif @tracked_target
      @tracked_target = nil unless scan_result&.any? { |r| r[:type] == :rubot }
      # Lost target - scan forward arc where we last saw them
      scan(angle: 120, distance: arena_diagonal * 0.5, velocity: true)
    else
      # No target - pulse to find one
      pulse(distance: arena_diagonal * 0.6)
    end

    shield(5) if energy > 50 && shield_level < 40
  end
end
