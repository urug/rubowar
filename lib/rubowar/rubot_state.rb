# frozen_string_literal: true

module Rubowar
  # Immutable snapshot of rubot state passed to rubots each tick
  RubotState = Data.define(
    :x, :y, :velocity_x, :velocity_y, :speed,
    :body_angle, :turret_angle,
    :health, :energy, :shield_level,
    :damage_dealt, :damage_taken, :size
  )
end
