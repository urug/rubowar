# frozen_string_literal: true

module Rubowar
  class Energon
    RADIUS = 8
    INITIAL_VALUE = 1
    GROWTH_RATE = 1.0

    attr_reader :x, :y, :spawn_tick

    def initialize(x:, y:, spawn_tick:)
      @x = x
      @y = y
      @spawn_tick = spawn_tick
    end

    def value(current_tick)
      ticks_alive = current_tick - @spawn_tick
      INITIAL_VALUE + (ticks_alive * GROWTH_RATE)
    end

    def value_int(current_tick)
      value(current_tick).floor
    end
  end
end
