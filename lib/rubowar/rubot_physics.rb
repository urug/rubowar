# frozen_string_literal: true

# [file]
# purpose = "Physics-related mutations for rubot actors"
# responsibility = "Movement, thrust, turret rotation, position/velocity changes"
# pattern = "Mixin Module"
#
# [module.RubotPhysics]
# purpose = "Provides physics mutation methods for actors"
# note = "Include alongside RubotActor in LocalActor, BasicActor, etc."
# dependencies = ["Physics (pure functions)", "RubotActor (state + energy)"]
#
# [methods]
# movement = ["thrust", "move", "apply_friction"]
# position = ["set_position", "adjust_position", "clamp_x", "clamp_y"]
# velocity = ["set_velocity", "adjust_velocity"]
# turret = ["turret_angle=", "turn_turret"]

module Rubowar
  module RubotPhysics
    # === Movement ===

    def apply_friction(friction)
      @velocity_x *= friction
      @velocity_y *= friction
    end

    def move
      @x += @velocity_x
      @y += @velocity_y
    end

    def thrust(speed:, angle:)
      NumericValidation.validate!(speed, name: "thrust speed", positive: true)
      NumericValidation.validate!(angle, name: "thrust angle")

      return false if @energy <= 0

      mass = Physics.mass_factor(radius)
      direction_multiplier = Physics.thrust_direction_multiplier(
        vx: @velocity_x, vy: @velocity_y,
        thrust_angle: angle, speed: self.speed
      )
      required_energy = Physics.thrust_cost(speed:, mass:, direction_multiplier:)

      if @energy >= required_energy
        @energy -= required_energy
        actual_speed = speed
      else
        actual_speed = Physics.thrust_speed_from_energy(energy: @energy, mass:, direction_multiplier:)
        @energy = 0
      end

      velocity = Physics.thrust_velocity(speed: actual_speed, angle:, mass:)
      adjust_velocity(dvx: velocity[:vx], dvy: velocity[:vy])
      true
    end

    # === Position ===

    def set_position(x:, y:)
      @x = x
      @y = y
      @position_set = true
    end

    def adjust_position(dx:, dy:)
      @x += dx
      @y += dy
    end

    def clamp_x(min:, max:)
      @x = @x.clamp(min, max)
    end

    def clamp_y(min:, max:)
      @y = @y.clamp(min, max)
    end

    # === Velocity ===

    def set_velocity(vx:, vy:)
      @velocity_x = vx
      @velocity_y = vy
    end

    def adjust_velocity(dvx:, dvy:)
      @velocity_x += dvx
      @velocity_y += dvy
    end

    # === Turret ===

    def turret_angle=(angle)
      NumericValidation.validate!(angle, name: "turret angle")
      @turret_angle = Physics.normalize_angle(angle)
    end

    def turn_turret(degrees)
      cost = (degrees.abs / Config::Combat::TURRET_TURN_DIVISOR).ceil
      return false unless spend_energy(cost)

      @turret_angle = Physics.normalize_angle(@turret_angle + degrees)
      true
    end
  end
end
