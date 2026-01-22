# frozen_string_literal: true

# [file]
# purpose = "Immutable value object for collision calculation results"
# responsibility = "Store pre-calculated collision response data"
# pattern = "Value Object using Data.define"
#
# [usage]
# context = "Created by Arena during collision detection phase"
# lifecycle = "Calculated for all collisions, then applied atomically"
# rationale = "Separates collision detection from application to prevent race conditions"

module Rubowar
  # Immutable collision response containing all physics adjustments
  # Calculated during detection phase, applied atomically afterward
  CollisionResponse = Data.define(
    :actor_a,           # First RubotActor in collision
    :actor_b,           # Second RubotActor in collision
    :pos_adjust_a_x,    # X position adjustment for actor A
    :pos_adjust_a_y,    # Y position adjustment for actor A
    :pos_adjust_b_x,    # X position adjustment for actor B
    :pos_adjust_b_y,    # Y position adjustment for actor B
    :vel_adjust_a_x,    # X velocity adjustment for actor A
    :vel_adjust_a_y,    # Y velocity adjustment for actor A
    :vel_adjust_b_x,    # X velocity adjustment for actor B
    :vel_adjust_b_y,    # Y velocity adjustment for actor B
    :damage_to_a,       # Collision damage to actor A
    :damage_to_b        # Collision damage to actor B
  ) do
    # Apply position adjustments to both actors
    def apply_positions!
      actor_a.adjust_position(dx: pos_adjust_a_x, dy: pos_adjust_a_y)
      actor_b.adjust_position(dx: pos_adjust_b_x, dy: pos_adjust_b_y)
    end

    # Apply velocity adjustments to both actors
    def apply_velocities!
      actor_a.adjust_velocity(dvx: vel_adjust_a_x, dvy: vel_adjust_a_y)
      actor_b.adjust_velocity(dvx: vel_adjust_b_x, dvy: vel_adjust_b_y)
    end

    # Apply damage and trigger callbacks for both actors
    def apply_damage_and_callbacks!
      actor_a.apply_collision_damage(damage_to_a)
      actor_b.apply_collision_damage(damage_to_b)

      actor_a.call_safely { |bot| bot.on_collision(other: actor_b.to_state) }
      actor_b.call_safely { |bot| bot.on_collision(other: actor_a.to_state) }
    end
  end
end
