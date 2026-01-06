# frozen_string_literal: true

module Rubowar
  # Immutable snapshot of arena state passed to robots each tick
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
