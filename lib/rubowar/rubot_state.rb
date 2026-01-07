# frozen_string_literal: true

# [file]
# purpose = "Immutable snapshot of rubot state passed to rubots each tick"
# responsibility = "Read-only view of rubot's own state"
# pattern = "Value Object (Data.define)"
#
# [RubotState]
# purpose = "Prevents rubots from modifying their own state directly"
# fields = ["x", "y", "velocity_x", "velocity_y", "speed", "turret_angle", "health", "energy", "shield_level", "damage_dealt", "damage_taken", "size"]
# immutable = true

module Rubowar
  RubotState = Data.define(
    :x, :y, :velocity_x, :velocity_y, :speed,
    :turret_angle,
    :health, :energy, :shield_level,
    :damage_dealt, :damage_taken, :size
  )
end
