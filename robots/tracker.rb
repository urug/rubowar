# frozen_string_literal: true

# A stationary turret that uses SimpleTargeting to track and shoot enemies.
# Large size provides 120 HP and 12 energy regen - tanky and high firepower.
class Tracker
  include Rubowar::Rubot
  include Rubowar::SimpleTargeting

  size :large

  def tick
    # Update target from last tick's sensors
    acquire_target_from_probe || acquire_target_from_pulse

    if target?
      aim_turret_at_target
      fire(12) if turret_aligned? && energy > 25
      probe(:position, :velocity) # Queue probe for next tick
    else
      pulse(distance: 500) # Queue pulse for next tick
    end

    shield(5) if energy > 50 && shield_level < 40
  end
end
