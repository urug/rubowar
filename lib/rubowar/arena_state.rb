# frozen_string_literal: true

# [file]
# purpose = "Immutable snapshot of arena state passed to rubots each tick"
# responsibility = "Read-only view of arena dimensions, energons, and game state"
# pattern = "Value Object (Data.define)"
#
# [ArenaState]
# purpose = "Provides rubots with arena info without exposing mutable state"
# fields = ["arena_width", "arena_height", "friction", "tick_number", "energons", "live_rubot_count"]
# immutable = true

module Rubowar
  ArenaState = Data.define(
    :arena_width, :arena_height, :friction, :tick_number,
    :energons, :live_rubot_count,
    :energon_spawn_interval, :energon_growth_rate
  ) do
    def initialize(
      arena_width: 800, arena_height: 600, friction: 0.95, tick_number: 0,
      energons: [], live_rubot_count: 0,
      energon_spawn_interval: 80, energon_growth_rate: 1.0
    )
      super
    end
  end
end
