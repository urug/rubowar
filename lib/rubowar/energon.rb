# frozen_string_literal: true

# [file]
# purpose = "Collectible energy pickups that spawn in the arena"
# responsibility = "Track position and calculate value based on age"
# pattern = "Entity"
#
# [class.Energon]
# purpose = "Energy pickup that grows more valuable over time"
# constants = { RADIUS = 8, INITIAL_VALUE = 1, GROWTH_RATE = 1.0 }
# value_formula = "INITIAL_VALUE + (ticks_alive * GROWTH_RATE)"
# collection = "Rubot touches energon -> gains value as energy"

module Rubowar
  class Energon
    attr_reader :x, :y, :spawn_tick

    def initialize(x:, y:, spawn_tick:)
      @x = x
      @y = y
      @spawn_tick = spawn_tick
    end

    def value(current_tick)
      ticks_alive = current_tick - @spawn_tick
      Config::Energon::INITIAL_VALUE + (ticks_alive * Config::Energon::GROWTH_RATE)
    end

    def value_int(current_tick)
      value(current_tick).floor
    end
  end
end
