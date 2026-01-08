# frozen_string_literal: true

# [file]
# purpose = "Immutable snapshot of arena state passed to rubots each chronons"
# responsibility = "Read-only view of arena dimensions, energons, and game state"
# pattern = "Value Object (Data.define)"
#
# [ArenaState]
# purpose = "Provides rubots with arena info without exposing mutable state"
# fields = ["arena_width", "arena_height", "friction", "chronons", "energons", "live_rubot_count"]
# immutable = true

module Rubowar
  ArenaState = Data.define(
    :arena_width, :arena_height, :friction, :chronons,
    :energons, :live_rubot_count,
    :energon_spawn_interval, :energon_growth_rate
  ) do
    def initialize(
      arena_width: Config::Arena::DEFAULT_WIDTH,
      arena_height: Config::Arena::DEFAULT_HEIGHT,
      friction: Config::Arena::DEFAULT_FRICTION,
      chronons: 0,
      energons: [],
      live_rubot_count: 0,
      energon_spawn_interval: Config::Arena::ENERGON_SPAWN_INTERVAL,
      energon_growth_rate: Config::Energon::GROWTH_RATE
    )
      super
    end
  end
end
