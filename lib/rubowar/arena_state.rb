# frozen_string_literal: true

module Rubowar
  # Immutable snapshot of arena state passed to robots each tick
  ArenaState = Data.define(:arena_width, :arena_height, :friction, :tick_number, :energons) do
    def initialize(arena_width: 800, arena_height: 600, friction: 0.95, tick_number: 0, energons: [])
      super
    end
  end
end
