# frozen_string_literal: true

require "test_helper"

describe Rubowar::Phases::Combat do
  def build_arena(width: 640, height: 640)
    Rubowar::Arena.new(width:, height:)
  end

  def build_actor(x: 100.0, y: 100.0, turret_angle: 0.0, energy: 100)
    klass = Class.new do
      include Rubowar::Rubot
      def act; end
    end
    actor = Rubowar::RubotActor.new(klass)
    actor.set_position(x:, y:)
    actor.set_turret_angle(turret_angle)
    actor.instance_variable_set(:@energy, energy)
    actor.reset_actions
    actor
  end

  describe ".execute" do
    it "processes fire actions and creates bullets" do
      arena = build_arena
      actor = build_actor(x: 300.0, y: 300.0, turret_angle: 0.0, energy: 50)
      arena.actors = [actor]

      # Queue fire action
      actor.instance.actions[:combat] << { type: :fire, energy: 10 }

      Rubowar::Phases::Combat.execute(arena:, actors: arena.actors)

      # Bullet should have been created
      _(arena.bullets.size).must_equal 1
      # Bullet should be traveling in turret direction (east)
      _(arena.bullets.first.velocity_x).must_be :>, 0
    end

    it "processes raise_shields actions" do
      arena = build_arena
      actor = build_actor(energy: 50)
      arena.actors = [actor]

      # Queue shield action
      actor.instance.actions[:combat] << { type: :shield, energy: 20 }

      Rubowar::Phases::Combat.execute(arena:, actors: arena.actors)

      # Shield level should have increased
      _(actor.shield_level).must_equal 20
    end

    it "updates bullet physics after processing actions" do
      arena = build_arena
      actor = build_actor(x: 300.0, y: 300.0, turret_angle: 0.0, energy: 50)
      arena.actors = [actor]

      # Create bullet
      bullet = Rubowar::Bullet.new(
        x: 100.0,
        y: 100.0,
        angle: 0.0,
        damage: 15,
        owner: actor
      )
      arena.bullets = [bullet]
      initial_x = bullet.x

      Rubowar::Phases::Combat.execute(arena:, actors: arena.actors)

      # Bullet should have moved
      _(bullet.x).must_be :>, initial_x
    end

    it "removes bullets that hit targets" do
      arena = build_arena
      shooter = build_actor(x: 100.0, y: 300.0, energy: 50)
      target = build_actor(x: 200.0, y: 300.0, energy: 50)
      arena.actors = [shooter, target]

      # Create bullet heading toward target
      bullet = Rubowar::Bullet.new(
        x: 180.0,
        y: 300.0,
        angle: 0.0,
        damage: 15,
        owner: shooter
      )
      arena.bullets = [bullet]
      initial_health = target.health

      Rubowar::Phases::Combat.execute(arena:, actors: arena.actors)

      # Bullet should have hit and been removed
      _(arena.bullets.size).must_equal 0
      # Target should have taken damage
      _(target.health).must_be :<, initial_health
    end

    it "removes bullets that go out of bounds" do
      arena = build_arena(width: 100, height: 100)
      actor = build_actor(energy: 50)
      arena.actors = [actor]

      # Create bullet near edge, traveling outward
      bullet = Rubowar::Bullet.new(
        x: 95.0,
        y: 50.0,
        angle: 0.0,
        damage: 15,
        owner: actor
      )
      arena.bullets = [bullet]

      Rubowar::Phases::Combat.execute(arena:, actors: arena.actors)

      # Bullet should have been removed
      _(arena.bullets.size).must_equal 0
    end

    it "skips dead actors" do
      arena = build_arena
      actor = build_actor(energy: 50)
      actor.instance_variable_set(:@health, 0)
      arena.actors = [actor]

      # Queue action for dead actor
      actor.instance.actions[:combat] << { type: :fire, energy: 10 }

      Rubowar::Phases::Combat.execute(arena:, actors: arena.actors)

      # No bullet should have been created
      _(arena.bullets.size).must_equal 0
    end

    it "returns failed actions when energy is insufficient" do
      arena = build_arena
      actor = build_actor(energy: 5)
      arena.actors = [actor]

      # Queue action that requires more energy than available
      actor.instance.actions[:combat] << { type: :fire, energy: 10 }

      failures = Rubowar::Phases::Combat.execute(arena:, actors: arena.actors)

      _(failures).must_be_kind_of Array
      _(failures.size).must_equal 1
      _(failures.first[:actor]).must_equal actor
    end

    it "applies error damage for invalid actions" do
      arena = build_arena
      actor = build_actor(energy: 50)
      arena.actors = [actor]
      initial_health = actor.health

      # Queue invalid action (negative energy)
      actor.instance.actions[:combat] << { type: :fire, energy: -10 }

      failures = Rubowar::Phases::Combat.execute(arena:, actors: arena.actors)

      _(actor.health).must_be :<, initial_health
      _(failures.first[:error]).must_be_kind_of Rubowar::InvalidActionError
    end

    it "fires bullets from post-movement positions" do
      arena = build_arena
      actor = build_actor(x: 300.0, y: 300.0, turret_angle: 0.0, energy: 50)
      arena.actors = [actor]

      # Note: In actual game flow, move phase happens before combat phase
      # This test just verifies that fire uses current position
      actor.set_position(x: 350.0, y: 300.0)

      actor.instance.actions[:combat] << { type: :fire, energy: 10 }

      Rubowar::Phases::Combat.execute(arena:, actors: arena.actors)

      # Bullet spawns at actor radius + bullet radius away (actor is at 350)
      # Medium bot radius is 20, bullet radius is 3, so bullet spawns at ~373
      _(arena.bullets.first.x).must_be :>, 350.0
      _(arena.bullets.first.x).must_be :<, 400.0
    end
  end
end
