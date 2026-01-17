# frozen_string_literal: true

require "securerandom"

# [file]
# purpose = "Projectile tracking for fired bullets"
# responsibility = "Position updates, collision detection, ownership"
# pattern = "Entity"
#
# [class.Bullet]
# purpose = "Represents a bullet in flight"
# constants = { SPEED = 18, RADIUS = 3 }
# damage = "Set by firing rubot (energy * 1.5)"
# note = "Bullets travel in straight lines, removed when out of bounds or hitting target"

module Rubowar
  class Bullet
    attr_reader :id, :x, :y, :velocity_x, :velocity_y, :damage, :owner, :radius

    def initialize(x:, y:, angle:, damage:, owner:)
      @id = "#{Config::Ids::BULLET_PREFIX}-#{SecureRandom.hex(4)}"
      @x = x.to_f
      @y = y.to_f
      @damage = damage
      @owner = owner
      @radius = Config::Combat::BULLET_RADIUS

      radians = angle * Math::PI / 180
      @velocity_x = Math.cos(radians) * Config::Combat::BULLET_SPEED
      @velocity_y = Math.sin(radians) * Config::Combat::BULLET_SPEED
    end

    def update
      @x += @velocity_x
      @y += @velocity_y
    end

    def out_of_bounds?(width, height)
      @x.negative? || @x > width || @y.negative? || @y > height
    end
  end
end
