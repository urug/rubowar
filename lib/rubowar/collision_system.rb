# frozen_string_literal: true

# [file]
# purpose = "Collision detection and resolution orchestration"
# responsibility = "Coordinate multi-phase collision handling for rubots and walls"
# pattern = "Module Functions (stateless orchestration)"
#
# [module.CollisionSystem]
# purpose = "Orchestrates collision detection, response calculation, and application"
# usage = "CollisionSystem.process_rubot_collisions(actors)"
# note = "Uses Physics for calculations, CollisionResponse for data transfer"
#
# [design]
# separation = "Physics = pure math, CollisionSystem = orchestration"
# phases = [
#   "1. Detect all collisions and calculate responses",
#   "2. Apply position adjustments atomically",
#   "3. Apply velocity changes atomically",
#   "4. Apply damage and callbacks atomically"
# ]
# rationale = "Atomic phases prevent race conditions and ensure fairness"

module Rubowar
  module CollisionSystem
    module_function

    # Process all rubot-rubot collisions in atomic phases
    # @param actors [Array<RubotActor>] All actors in the arena
    # @return [Array<CollisionResponse>] All collision responses (for testing/events)
    def process_rubot_collisions(actors)
      # Phase 1: Detect all collisions and calculate responses
      collision_responses = detect_collisions(actors)

      # Phase 2: Apply all position adjustments atomically
      collision_responses.each(&:apply_positions!)

      # Phase 3: Apply all velocity changes atomically
      collision_responses.each(&:apply_velocities!)

      # Phase 4: Apply damage and callbacks (after all physics resolved)
      collision_responses.each(&:apply_damage_and_callbacks!)

      collision_responses
    end

    # Detect collisions between all actor pairs
    # @param actors [Array<RubotActor>] All actors in the arena
    # @return [Array<CollisionResponse>] Collision responses for overlapping pairs
    def detect_collisions(actors)
      responses = []

      actors.combination(2).each do |actor_a, actor_b|
        next if actor_a.dead? || actor_b.dead?

        distance = Physics.distance(x1: actor_a.x, y1: actor_a.y, x2: actor_b.x, y2: actor_b.y)
        min_distance = actor_a.radius + actor_b.radius

        next unless distance < min_distance

        response = build_collision_response(actor_a:, actor_b:, distance:, min_distance:)
        responses << response
      end

      responses
    end

    # Build a CollisionResponse with all physics calculations
    # @param actor_a [RubotActor] First actor in collision
    # @param actor_b [RubotActor] Second actor in collision
    # @param distance [Float] Current distance between actors
    # @param min_distance [Float] Minimum allowed distance (sum of radii)
    # @return [CollisionResponse] Immutable response with all adjustments
    def build_collision_response(actor_a:, actor_b:, distance:, min_distance:)
      overlap = min_distance - distance
      mass_a = Physics.mass_factor(actor_a.radius)
      mass_b = Physics.mass_factor(actor_b.radius)

      # separation_direction returns unit vector pointing from B to A (direction to push A)
      # collision_bounce expects normal pointing from A to B, so we negate
      sep_x, sep_y = Physics.separation_direction(
        a_x: actor_a.x, a_y: actor_a.y, b_x: actor_b.x, b_y: actor_b.y, distance:,
        a_vx: actor_a.velocity_x, a_vy: actor_a.velocity_y,
        b_vx: actor_b.velocity_x, b_vy: actor_b.velocity_y
      )
      nx = -sep_x
      ny = -sep_y

      separation = Physics.collision_separation(
        a_x: actor_a.x, a_y: actor_a.y,
        b_x: actor_b.x, b_y: actor_b.y,
        distance:, overlap:,
        a_vx: actor_a.velocity_x, a_vy: actor_a.velocity_y,
        b_vx: actor_b.velocity_x, b_vy: actor_b.velocity_y
      )

      bounce = Physics.collision_bounce(
        a_vx: actor_a.velocity_x, a_vy: actor_a.velocity_y,
        b_vx: actor_b.velocity_x, b_vy: actor_b.velocity_y,
        nx:, ny:, mass_a:, mass_b:
      )

      CollisionResponse.new(
        actor_a:,
        actor_b:,
        pos_adjust_a_x: separation[:a_x],
        pos_adjust_a_y: separation[:a_y],
        pos_adjust_b_x: separation[:b_x],
        pos_adjust_b_y: separation[:b_y],
        vel_adjust_a_x: bounce[:a_vx],
        vel_adjust_a_y: bounce[:a_vy],
        vel_adjust_b_x: bounce[:b_vx],
        vel_adjust_b_y: bounce[:b_vy],
        damage_to_a: Physics.collision_damage(
          rel_vx: actor_b.velocity_x - actor_a.velocity_x,
          rel_vy: actor_b.velocity_y - actor_a.velocity_y,
          mass: mass_b
        ),
        damage_to_b: Physics.collision_damage(
          rel_vx: actor_a.velocity_x - actor_b.velocity_x,
          rel_vy: actor_a.velocity_y - actor_b.velocity_y,
          mass: mass_a
        )
      )
    end

    # Process wall collision for a single actor
    # @param actor [RubotActor] The actor to check
    # @param arena_width [Numeric] Arena width
    # @param arena_height [Numeric] Arena height
    # @return [Hash, nil] Wall collision data { actor:, damage:, walls: [] } or nil if no collision
    def process_wall_collision(actor:, arena_width:, arena_height:)
      total_damage = 0
      walls = []

      # Check left wall
      if (actor.x - actor.radius).negative?
        actor.clamp_x(min: actor.radius, max: arena_width - actor.radius)
        walls << :left
        total_damage += apply_wall_bounce(actor:, normal_x: 1.0, normal_y: 0.0)
      # Check right wall
      elsif actor.x + actor.radius > arena_width
        actor.clamp_x(min: actor.radius, max: arena_width - actor.radius)
        walls << :right
        total_damage += apply_wall_bounce(actor:, normal_x: -1.0, normal_y: 0.0)
      end

      # Check bottom wall
      if (actor.y - actor.radius).negative?
        actor.clamp_y(min: actor.radius, max: arena_height - actor.radius)
        walls << :bottom
        total_damage += apply_wall_bounce(actor:, normal_x: 0.0, normal_y: 1.0)
      # Check top wall
      elsif actor.y + actor.radius > arena_height
        actor.clamp_y(min: actor.radius, max: arena_height - actor.radius)
        walls << :top
        total_damage += apply_wall_bounce(actor:, normal_x: 0.0, normal_y: -1.0)
      end

      return nil if walls.empty?

      actor.apply_collision_damage(total_damage)
      actor.call_safely(&:on_wall)

      { actor:, damage: total_damage, walls: }
    end

    # Calculate and apply wall bounce physics
    # @param actor [RubotActor] The actor bouncing off wall
    # @param normal_x [Float] Wall normal X component
    # @param normal_y [Float] Wall normal Y component
    # @return [Numeric] Damage from the wall impact
    def apply_wall_bounce(actor:, normal_x:, normal_y:)
      mass = Physics.mass_factor(actor.radius)

      damage = Physics.wall_damage(
        vx: actor.velocity_x, vy: actor.velocity_y,
        normal_x:, normal_y:, mass:
      )

      if (result = Physics.wall_bounce(
        vx: actor.velocity_x, vy: actor.velocity_y,
        normal_x:, normal_y:, bot_mass: mass
      ))
        actor.set_velocity(vx: result[:vx], vy: result[:vy])
      end

      damage
    end
  end
end
