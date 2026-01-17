# frozen_string_literal: true

require "test_helper"

class CollisionTestBot
  include Rubowar::Rubot

  size :medium
  def act; end
end

class SmallCollisionBot
  include Rubowar::Rubot

  size :small
  def act; end
end

class LargeCollisionBot
  include Rubowar::Rubot

  size :large
  def act; end
end

def build_collision_actor(x:, y:, klass: CollisionTestBot)
  actor = Rubowar::LocalActor.new(klass)
  actor.x = x
  actor.y = y
  actor
end

describe Rubowar::CollisionSystem do
  describe ".process_rubot_collisions" do
    it "returns empty array when no collisions occur" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 300, y: 300)

      result = Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b])

      _(result).must_be_empty
    end

    it "returns collision responses for overlapping actors" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)

      result = Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b])

      _(result.length).must_equal 1
      _(result.first).must_be_instance_of Rubowar::CollisionResponse
    end

    it "separates overlapping actors to non-overlapping positions" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)

      Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b])

      distance = Rubowar::Physics.distance(x1: actor_a.x, y1: actor_a.y, x2: actor_b.x, y2: actor_b.y)
      min_allowed = actor_a.radius + actor_b.radius
      _(distance).must_be :>=, min_allowed - 1
    end

    it "applies velocity changes based on collision physics" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)
      actor_a.velocity_x = 5.0
      actor_b.velocity_x = -5.0

      Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b])

      # After collision, velocities should be exchanged/modified
      _(actor_a.velocity_x).must_be :<, 5.0
      _(actor_b.velocity_x).must_be :>, -5.0
    end

    it "applies damage to both actors" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)
      actor_a.velocity_x = 5.0
      actor_b.velocity_x = -5.0
      initial_health_a = actor_a.health
      initial_health_b = actor_b.health

      Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b])

      _(actor_a.health).must_be :<, initial_health_a
      _(actor_b.health).must_be :<, initial_health_b
    end

    it "skips dead actors" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)
      actor_a.health = 0
      initial_health_b = actor_b.health

      result = Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b])

      _(result).must_be_empty
      _(actor_b.health).must_equal initial_health_b
    end

    it "handles multiple simultaneous collisions" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)
      actor_c = build_collision_actor(x: 100, y: 110)

      result = Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b, actor_c])

      # All 3 pairs collide in triangular arrangement (A-B, A-C, B-C)
      _(result.length).must_equal 3
    end

    it "handles different sized actors" do
      small = build_collision_actor(x: 100, y: 100, klass: SmallCollisionBot)
      # Position large bot so they overlap (radii 8+12=20, so < 20 apart)
      large = build_collision_actor(x: 115, y: 100, klass: LargeCollisionBot)
      small.velocity_x = 5.0
      large.velocity_x = -5.0

      Rubowar::CollisionSystem.process_rubot_collisions([small, large])

      # Small bot should be pushed more than large bot
      _(small.x).must_be :<, 100 # Pushed left
      _(large.x).must_be :>, 115 # Pushed right (less)
    end
  end

  describe ".detect_collisions" do
    it "returns empty array when actors dont overlap" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 200, y: 200)

      result = Rubowar::CollisionSystem.detect_collisions([actor_a, actor_b])

      _(result).must_be_empty
    end

    it "detects overlapping actors" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)

      result = Rubowar::CollisionSystem.detect_collisions([actor_a, actor_b])

      _(result.length).must_equal 1
    end

    it "skips dead actors" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)
      actor_a.health = 0

      result = Rubowar::CollisionSystem.detect_collisions([actor_a, actor_b])

      _(result).must_be_empty
    end
  end

  describe ".build_collision_response" do
    it "creates a CollisionResponse with correct actors" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)
      distance = Rubowar::Physics.distance(x1: actor_a.x, y1: actor_a.y, x2: actor_b.x, y2: actor_b.y)
      min_distance = actor_a.radius + actor_b.radius

      response = Rubowar::CollisionSystem.build_collision_response(
        actor_a:, actor_b:, distance:, min_distance:
      )

      _(response.actor_a).must_equal actor_a
      _(response.actor_b).must_equal actor_b
    end

    it "calculates position adjustments" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)
      distance = Rubowar::Physics.distance(x1: actor_a.x, y1: actor_a.y, x2: actor_b.x, y2: actor_b.y)
      min_distance = actor_a.radius + actor_b.radius

      response = Rubowar::CollisionSystem.build_collision_response(
        actor_a:, actor_b:, distance:, min_distance:
      )

      # Actors should be pushed apart (A pushed left, B pushed right)
      _(response.pos_adjust_a_x).must_be :<, 0
      _(response.pos_adjust_b_x).must_be :>, 0
    end

    it "calculates damage based on relative velocity" do
      actor_a = build_collision_actor(x: 100, y: 100)
      actor_b = build_collision_actor(x: 110, y: 100)
      actor_a.velocity_x = 5.0
      actor_b.velocity_x = -5.0
      distance = Rubowar::Physics.distance(x1: actor_a.x, y1: actor_a.y, x2: actor_b.x, y2: actor_b.y)
      min_distance = actor_a.radius + actor_b.radius

      response = Rubowar::CollisionSystem.build_collision_response(
        actor_a:, actor_b:, distance:, min_distance:
      )

      _(response.damage_to_a).must_be :>, 0
      _(response.damage_to_b).must_be :>, 0
    end
  end

  describe ".process_wall_collision" do
    it "returns false when actor is not touching wall" do
      actor = build_collision_actor(x: 100, y: 100)

      result = Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: 800, arena_height: 600
      )

      _(result).must_be_nil
    end

    it "returns collision data when actor touches left wall" do
      actor = build_collision_actor(x: 100, y: 100)
      actor.x = actor.radius - 2 # Position overlapping left wall
      actor.velocity_x = -10.0

      result = Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: 800, arena_height: 600
      )

      _(result).wont_be_nil
      _(result[:walls]).must_include :left
    end

    it "returns collision data when actor touches right wall" do
      actor = build_collision_actor(x: 100, y: 100)
      actor.x = 800 - actor.radius + 2 # Position overlapping right wall
      actor.velocity_x = 10.0

      result = Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: 800, arena_height: 600
      )

      _(result).wont_be_nil
      _(result[:walls]).must_include :right
    end

    it "returns collision data when actor touches bottom wall" do
      actor = build_collision_actor(x: 100, y: 100)
      actor.y = actor.radius - 2 # Position overlapping bottom wall
      actor.velocity_y = -10.0

      result = Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: 800, arena_height: 600
      )

      _(result).wont_be_nil
      _(result[:walls]).must_include :bottom
    end

    it "returns collision data when actor touches top wall" do
      actor = build_collision_actor(x: 100, y: 100)
      actor.y = 600 - actor.radius + 2 # Position overlapping top wall
      actor.velocity_y = 10.0

      result = Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: 800, arena_height: 600
      )

      _(result).wont_be_nil
      _(result[:walls]).must_include :top
    end

    it "clamps actor position to arena bounds" do
      actor = build_collision_actor(x: 100, y: 100)
      actor.x = actor.radius - 5 # Position well inside left wall
      actor.velocity_x = -10.0

      Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: 800, arena_height: 600
      )

      _(actor.x).must_be :>=, actor.radius
    end

    it "reverses velocity on wall bounce" do
      actor = build_collision_actor(x: 100, y: 100)
      actor.x = actor.radius - 2 # Position overlapping left wall
      actor.velocity_x = -10.0
      actor.velocity_y = 0.0

      Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: 800, arena_height: 600
      )

      _(actor.velocity_x).must_be :>, 0
    end

    it "applies damage on wall collision" do
      actor = build_collision_actor(x: 100, y: 100)
      actor.x = actor.radius - 2 # Position overlapping left wall
      actor.velocity_x = -10.0
      initial_health = actor.health

      Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: 800, arena_height: 600
      )

      _(actor.health).must_be :<, initial_health
    end

    it "handles corner collisions" do
      actor = build_collision_actor(x: 100, y: 100)
      actor.x = actor.radius - 2 # Position overlapping left wall
      actor.y = actor.radius - 2 # Position overlapping bottom wall
      actor.velocity_x = -10.0
      actor.velocity_y = -10.0

      Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: 800, arena_height: 600
      )

      _(actor.velocity_x).must_be :>, 0
      _(actor.velocity_y).must_be :>, 0
    end
  end

  describe ".apply_wall_bounce" do
    it "returns damage from wall impact" do
      actor = build_collision_actor(x: 10, y: 100)
      actor.velocity_x = -10.0

      damage = Rubowar::CollisionSystem.apply_wall_bounce(
        actor:, normal_x: 1.0, normal_y: 0.0
      )

      _(damage).must_be :>, 0
    end

    it "modifies actor velocity" do
      actor = build_collision_actor(x: 10, y: 100)
      actor.velocity_x = -10.0

      Rubowar::CollisionSystem.apply_wall_bounce(
        actor:, normal_x: 1.0, normal_y: 0.0
      )

      _(actor.velocity_x).must_be :>, 0
    end
  end
end
