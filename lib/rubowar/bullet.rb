# frozen_string_literal: true

module Rubowar
  class Bullet
    SPEED = 18
    RADIUS = 3

    attr_reader :x, :y, :velocity_x, :velocity_y, :damage, :owner, :radius

    def initialize(x:, y:, angle:, damage:, owner:)
      @x = x.to_f
      @y = y.to_f
      @damage = damage.to_f
      @owner = owner
      @radius = RADIUS

      radians = angle * Math::PI / 180
      @velocity_x = Math.cos(radians) * SPEED
      @velocity_y = Math.sin(radians) * SPEED
    end

    def update
      @x += @velocity_x
      @y += @velocity_y
    end

    def out_of_bounds?(width, height)
      @x < 0 || @x > width || @y < 0 || @y > height
    end
  end
end
