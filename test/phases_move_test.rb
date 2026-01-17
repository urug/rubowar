# frozen_string_literal: true

require "test_helper"

describe Rubowar::Phases::Move do
  def build_arena(width: 640, height: 640)
    Rubowar::Arena.new(width:, height:, event_bus: Rubowar::EventBus.new)
  end

  def build_actor(x: 100.0, y: 100.0, turret_angle: 0.0, energy: 100)
    klass = Class.new do
      include Rubowar::Rubot

      def act; end
    end
    actor = Rubowar::LocalActor.new(klass)
    actor.set_position(x:, y:)
    actor.turret_angle = turret_angle
    actor.instance_variable_set(:@energy, energy)
    actor.reset_actions
    actor
  end

  describe ".execute" do
    it "processes thrust actions" do
      arena = build_arena
      actor = build_actor(x: 300.0, y: 300.0, energy: 50)
      arena.actors = [actor]

      # Queue thrust action
      actor.instance.actions[:move] << { type: :thrust, speed: 5, angle: 0 }

      Rubowar::Phases::Move.execute(arena:, actors: arena.actors)

      # Actor should have velocity in the east direction
      _(actor.velocity_x).must_be :>, 0
      _(actor.velocity_y).must_be_within_delta 0, 0.1
    end

    it "processes rotate_turret actions" do
      arena = build_arena
      actor = build_actor(turret_angle: 0.0, energy: 50)
      arena.actors = [actor]

      # Queue turret rotation
      actor.instance.actions[:move] << { type: :rotate_turret, degrees: 45 }

      Rubowar::Phases::Move.execute(arena:, actors: arena.actors)

      # Turret should have rotated
      _(actor.turret_angle).must_equal 45.0
    end

    it "applies physics after processing all actions" do
      arena = build_arena
      actor = build_actor(x: 300.0, y: 300.0, energy: 50)
      actor.set_velocity(vx: 10.0, vy: 0.0)
      arena.actors = [actor]
      initial_x = actor.x

      Rubowar::Phases::Move.execute(arena:, actors: arena.actors)

      # Actor should have moved due to velocity
      _(actor.x).must_be :>, initial_x
      # Friction should have been applied (velocity < 10)
      _(actor.velocity_x).must_be :<, 10.0
    end

    it "handles wall collisions during physics" do
      arena = build_arena
      actor = build_actor(x: 20.0, y: 300.0, energy: 50)
      actor.set_velocity(vx: -20.0, vy: 0.0)
      arena.actors = [actor]
      initial_health = actor.health

      Rubowar::Phases::Move.execute(arena:, actors: arena.actors)

      # Actor should bounce off wall
      _(actor.velocity_x).must_be :>=, 0 # Bounced back
      # Actor should take damage from wall collision
      _(actor.health).must_be :<, initial_health
    end

    it "handles rubot-to-rubot collisions" do
      arena = build_arena
      actor_a = build_actor(x: 100.0, y: 300.0, energy: 50)
      actor_b = build_actor(x: 130.0, y: 300.0, energy: 50)
      actor_a.set_velocity(vx: 10.0, vy: 0.0)
      actor_b.set_velocity(vx: -10.0, vy: 0.0)
      arena.actors = [actor_a, actor_b]

      initial_health_a = actor_a.health
      initial_health_b = actor_b.health

      Rubowar::Phases::Move.execute(arena:, actors: arena.actors)

      # Both should take collision damage
      _(actor_a.health).must_be :<, initial_health_a
      _(actor_b.health).must_be :<, initial_health_b
    end

    it "skips dead actors" do
      arena = build_arena
      actor = build_actor(energy: 50)
      actor.instance_variable_set(:@health, 0)
      arena.actors = [actor]

      # Queue action for dead actor
      actor.instance.actions[:move] << { type: :thrust, speed: 5, angle: 0 }

      Rubowar::Phases::Move.execute(arena:, actors: arena.actors)

      # Dead actor should not have moved
      _(actor.velocity_x).must_equal 0
      _(actor.velocity_y).must_equal 0
    end

    it "returns failed actions when energy is insufficient" do
      arena = build_arena
      actor = build_actor(energy: 0)
      arena.actors = [actor]

      # Queue action that requires energy
      actor.instance.actions[:move] << { type: :rotate_turret, degrees: 45 }

      failures = Rubowar::Phases::Move.execute(arena:, actors: arena.actors)

      _(failures).must_be_kind_of Array
      _(failures.size).must_equal 1
      _(failures.first[:actor]).must_equal actor
    end

    it "applies error damage for invalid actions" do
      arena = build_arena
      actor = build_actor(energy: 50)
      arena.actors = [actor]
      initial_health = actor.health

      # Queue invalid action (negative speed)
      actor.instance.actions[:move] << { type: :thrust, speed: -5, angle: 0 }

      failures = Rubowar::Phases::Move.execute(arena:, actors: arena.actors)

      _(actor.health).must_be :<, initial_health
      _(failures.first[:error]).must_be_kind_of Rubowar::InvalidActionError
    end
  end
end
