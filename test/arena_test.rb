# frozen_string_literal: true

require "test_helper"

class ProbeTestBot
  include Rubowar::Rubot

  size :medium
  def act; end
end

class SmallProbeTestBot
  include Rubowar::Rubot

  size :small
  def act; end
end

class LargeProbeTestBot
  include Rubowar::Rubot

  size :large
  def act; end
end

def build_arena(event_bus: Rubowar::EventBus.new)
  Rubowar::Arena.new(width: 800, height: 600, event_bus:)
end

def build_actor(x:, y:, turret_angle: 0, klass: ProbeTestBot)
  actor = Rubowar::LocalActor.new(klass)
  actor.x = x
  actor.y = y
  actor.turret_angle = turret_angle
  actor
end

describe Rubowar::Arena do
  describe "initialization" do
    it "sets width and height" do
      arena = Rubowar::Arena.new(width: 1000, height: 800, event_bus: Rubowar::EventBus.new)

      _(arena.width).must_equal 1000
      _(arena.height).must_equal 800
    end

    it "uses default values" do
      arena = Rubowar::Arena.new(event_bus: Rubowar::EventBus.new)

      _(arena.width).must_equal Rubowar::Config::Arena::DEFAULT_WIDTH
      _(arena.height).must_equal Rubowar::Config::Arena::DEFAULT_HEIGHT
      _(arena.friction).must_equal Rubowar::Config::Arena::DEFAULT_FRICTION
    end

    it "starts with empty bullets and actors" do
      arena = Rubowar::Arena.new(event_bus: Rubowar::EventBus.new)

      _(arena.bullets).must_equal []
      _(arena.actors).must_equal []
      _(arena.energons).must_equal []
    end
  end

  describe "#arena_diagonal" do
    it "calculates diagonal length" do
      arena = build_arena

      result = arena.arena_diagonal

      expected = Math.sqrt((800**2) + (600**2))
      _(result).must_equal expected
    end
  end

  describe "#spawn_wall_buffer" do
    it "returns buffer based on smaller dimension" do
      arena = build_arena

      result = arena.spawn_wall_buffer

      expected = (600 * Rubowar::Config::Arena::SPAWN_WALL_BUFFER_RATIO).round
      _(result).must_equal expected
    end
  end

  describe "#spawn_min_distance" do
    it "returns minimum spawn distance based on diagonal" do
      arena = build_arena

      result = arena.spawn_min_distance

      expected = (arena.arena_diagonal * Rubowar::Config::Arena::SPAWN_MIN_DISTANCE_RATIO).round
      _(result).must_equal expected
    end
  end

  describe "#spawn_max_distance" do
    it "returns maximum spawn distance based on diagonal" do
      arena = build_arena

      result = arena.spawn_max_distance

      expected = (arena.arena_diagonal * Rubowar::Config::Arena::SPAWN_MAX_DISTANCE_RATIO).round
      _(result).must_equal expected
    end
  end

  describe "#spawn_rubots" do
    it "places actors in arena" do
      arena = build_arena
      actors = [Rubowar::LocalActor.new(ProbeTestBot), Rubowar::LocalActor.new(SmallProbeTestBot)]

      arena.spawn_rubots(actors)

      _(arena.actors.length).must_equal 2
      _(arena.actors[0].instance).must_be_instance_of ProbeTestBot
      _(arena.actors[1].instance).must_be_instance_of SmallProbeTestBot
    end

    it "positions actors within arena bounds" do
      arena = build_arena
      actors = [Rubowar::LocalActor.new(ProbeTestBot), Rubowar::LocalActor.new(ProbeTestBot)]

      arena.spawn_rubots(actors)

      arena.actors.each do |actor|
        _(actor.x).must_be :>, actor.radius
        _(actor.x).must_be :<, arena.width - actor.radius
        _(actor.y).must_be :>, actor.radius
        _(actor.y).must_be :<, arena.height - actor.radius
      end
    end

    it "sets random turret angles" do
      arena = build_arena
      actors = [Rubowar::LocalActor.new(ProbeTestBot)]

      arena.spawn_rubots(actors)

      # Turret angles are normalized to -180..180 range
      _(arena.actors[0].turret_angle).must_be :>=, -180
      _(arena.actors[0].turret_angle).must_be :<=, 180
    end
  end

  describe "#to_state" do
    it "returns ArenaState with current values" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      arena.actors = [actor]

      state = arena.to_state(50)

      _(state).must_be_instance_of Rubowar::ArenaState
      _(state.arena_width).must_equal 800
      _(state.arena_height).must_equal 600
      _(state.chronon).must_equal 50
      _(state.live_rubot_count).must_equal 1
    end

    it "converts energons to hash format" do
      arena = build_arena
      energon = Rubowar::Energon.spawn(x: 200.0, y: 300.0, spawn_chronon: 10)
      arena.energons = [energon]

      state = arena.to_state(50)

      _(state.energons).must_equal [{ x: 200.0, y: 300.0 }]
    end
  end

  describe "#regenerate_and_degrade" do
    it "regenerates energy for alive actors" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.energy = 50
      arena.actors = [actor]

      arena.regenerate_and_degrade

      _(actor.energy).must_equal 60
    end

    it "degrades shields for alive actors" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.shield_level = 100
      arena.actors = [actor]

      arena.regenerate_and_degrade

      _(actor.shield_level).must_equal 88
    end

    it "skips dead actors" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.health = 0
      actor.energy = 50
      arena.actors = [actor]

      arena.regenerate_and_degrade

      _(actor.energy).must_equal 50
    end
  end

  describe "#process_action" do
    it "processes thrust action" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      arena.actors = [actor]

      result = arena.process_action(actor:, action: { type: :thrust, speed: 3, angle: 0 })

      _(result).must_equal true
      _(actor.velocity_x).must_be :>, 0
    end

    it "processes turret action" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [actor]

      result = arena.process_action(actor:, action: { type: :rotate_turret, degrees: 45 })

      _(result).must_equal true
      _(actor.turret_angle).must_equal 45.0
    end

    it "processes fire action" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [actor]

      result = arena.process_action(actor:, action: { type: :fire, energy: 10 })

      _(result).must_equal true
      _(arena.bullets.length).must_equal 1
    end

    it "processes shield action" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      arena.actors = [actor]

      result = arena.process_action(actor:, action: { type: :shield, energy: 20 })

      _(result).must_equal true
      _(actor.shield_level).must_equal 20
    end

    it "returns false for unknown action" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)

      result = arena.process_action(actor:, action: { type: :unknown })

      _(result).must_equal false
    end
  end

  describe "#process_fire" do
    it "creates bullet at turret position" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [actor]

      arena.process_fire(actor:, energy: 10)

      _(arena.bullets.length).must_equal 1
      bullet = arena.bullets.first
      _(bullet.x).must_be :>, actor.x
    end

    it "calculates damage from energy" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [actor]

      arena.process_fire(actor:, energy: 10)

      bullet = arena.bullets.first
      expected_damage = (10 * Rubowar::Config::Combat::FIRE_DAMAGE_MULTIPLIER).ceil
      _(bullet.damage).must_equal expected_damage
    end

    it "spends energy" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      actor.energy = 50
      arena.actors = [actor]

      arena.process_fire(actor:, energy: 10)

      _(actor.energy).must_equal 40
    end

    it "returns false when insufficient energy" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      actor.energy = 5
      arena.actors = [actor]

      result = arena.process_fire(actor:, energy: 10)

      _(result).must_equal false
      _(arena.bullets).must_be_empty
    end

    it "rejects NaN energy" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [actor]

      assert_raises(Rubowar::InvalidActionError) do
        arena.process_fire(actor:, energy: Float::NAN)
      end
    end

    it "rejects Infinity energy" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [actor]

      assert_raises(Rubowar::InvalidActionError) do
        arena.process_fire(actor:, energy: Float::INFINITY)
      end
    end

    it "rejects non-positive energy" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [actor]

      assert_raises(Rubowar::InvalidActionError) do
        arena.process_fire(actor:, energy: 0)
      end
    end
  end

  describe "#check_bullet_hit" do
    it "returns true when bullet hits actor" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      shooter = build_actor(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: shooter)
      arena.actors = [actor, shooter]

      result = arena.check_bullet_hit(bullet)

      _(result).must_equal true
    end

    it "applies damage to hit actor" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      shooter = build_actor(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: shooter)
      initial_health = actor.health
      arena.actors = [actor, shooter]

      arena.check_bullet_hit(bullet)

      _(actor.health).must_equal initial_health - 15
    end

    it "tracks damage dealt for shooter" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      shooter = build_actor(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: shooter)
      arena.actors = [actor, shooter]

      arena.check_bullet_hit(bullet)

      _(shooter.damage_dealt).must_equal 15
    end

    it "does not track self-damage" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: actor)
      arena.actors = [actor]

      arena.check_bullet_hit(bullet)

      _(actor.damage_dealt).must_equal 0
    end

    it "returns false when bullet misses" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 500, y: 500, angle: 0, damage: 15, owner: actor)
      arena.actors = [actor]

      result = arena.check_bullet_hit(bullet)

      _(result).must_equal false
    end

    it "ignores dead actors" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.health = 0
      shooter = build_actor(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: shooter)
      arena.actors = [actor, shooter]

      result = arena.check_bullet_hit(bullet)

      _(result).must_equal false
    end

    it "returns false when bullet at exact collision boundary" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      shooter = build_actor(x: 300, y: 300)
      # Position bullet exactly at collision boundary: distance = bullet.radius + actor.radius
      # Medium actor radius = 20, bullet radius = 3, so boundary = 23
      # Place bullet 23 units to the right of actor center
      bullet = Rubowar::Bullet.new(x: 100 + 23, y: 100, angle: 180, damage: 15, owner: shooter)
      arena.actors = [actor, shooter]

      # Distance is exactly 23 which equals bullet.radius (3) + actor.radius (20)
      # This should NOT be a hit since check uses distance < sum of radii (strict less than)
      result = arena.check_bullet_hit(bullet)

      _(result).must_equal false
    end

    it "returns true when bullet just inside collision boundary" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      shooter = build_actor(x: 300, y: 300)
      # Position bullet just inside collision boundary (22.9 < 23)
      bullet = Rubowar::Bullet.new(x: 100 + 22.9, y: 100, angle: 180, damage: 15, owner: shooter)
      arena.actors = [actor, shooter]

      result = arena.check_bullet_hit(bullet)

      _(result).must_equal true
    end

    it "returns false when bullet just outside collision boundary" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      shooter = build_actor(x: 300, y: 300)
      # Position bullet just outside collision boundary (23.1 > 23)
      bullet = Rubowar::Bullet.new(x: 100 + 23.1, y: 100, angle: 180, damage: 15, owner: shooter)
      arena.actors = [actor, shooter]

      result = arena.check_bullet_hit(bullet)

      _(result).must_equal false
    end
  end

  describe "CollisionSystem.process_rubot_collisions" do
    it "separates overlapping actors" do
      actor_a = build_actor(x: 100, y: 100)
      actor_b = build_actor(x: 110, y: 100) # Overlapping (distance < sum of radii)

      Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b])

      distance = Math.sqrt(((actor_a.x - actor_b.x)**2) + ((actor_a.y - actor_b.y)**2))
      _(distance).must_be :>=, actor_a.radius + actor_b.radius - 1
    end

    it "applies collision damage" do
      actor_a = build_actor(x: 100, y: 100)
      actor_b = build_actor(x: 110, y: 100)
      actor_a.velocity_x = 5.0
      actor_b.velocity_x = -5.0
      initial_health_a = actor_a.health
      initial_health_b = actor_b.health

      Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b])

      _(actor_a.health).must_be :<, initial_health_a
      _(actor_b.health).must_be :<, initial_health_b
    end

    it "ignores dead actors" do
      actor_a = build_actor(x: 100, y: 100)
      actor_b = build_actor(x: 110, y: 100)
      actor_a.health = 0
      initial_health_b = actor_b.health

      Rubowar::CollisionSystem.process_rubot_collisions([actor_a, actor_b])

      _(actor_b.health).must_equal initial_health_b
    end
  end

  describe "#update_rubot_physics" do
    it "applies friction to actors" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.velocity_x = 10.0
      actor.velocity_y = 0.0
      arena.actors = [actor]

      arena.update_rubot_physics

      _(actor.velocity_x).must_be :<, 10.0
    end

    it "moves actors" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.velocity_x = 10.0
      actor.velocity_y = 0.0
      arena.actors = [actor]

      arena.update_rubot_physics

      _(actor.x).must_be :>, 100.0
    end

    it "skips dead actors" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.velocity_x = 10.0
      actor.health = 0
      arena.actors = [actor]

      arena.update_rubot_physics

      _(actor.x).must_equal 100.0
    end
  end

  describe "#update_bullets" do
    it "moves bullets" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 200, y: 200, angle: 0, damage: 10, owner: actor)
      arena.actors = [actor]
      arena.bullets = [bullet]

      arena.update_bullets

      _(bullet.x).must_be :>, 200
    end

    it "removes bullets that hit actors" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      shooter = build_actor(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 10, owner: shooter)
      arena.actors = [actor, shooter]
      arena.bullets = [bullet]

      arena.update_bullets

      _(arena.bullets).must_be_empty
    end

    it "removes bullets that leave arena" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 850, y: 200, angle: 0, damage: 10, owner: actor)
      arena.actors = [actor]
      arena.bullets = [bullet]

      arena.update_bullets

      _(arena.bullets).must_be_empty
    end
  end

  describe "CollisionSystem.process_wall_collision" do
    it "bounces more for small bots and less for large bots" do
      arena = build_arena
      small = build_actor(x: 10, y: 100, klass: SmallProbeTestBot)
      medium = build_actor(x: 10, y: 200)
      large = build_actor(x: 10, y: 300, klass: LargeProbeTestBot)
      [small, medium, large].each do |actor|
        actor.velocity_x = -10.0
        actor.velocity_y = 0.0

        Rubowar::CollisionSystem.process_wall_collision(
          actor:, arena_width: arena.width, arena_height: arena.height
        )
      end

      # Wall mass = 24, wall restitution = 0.2 (sticky walls)
      # Small (0.64): bounces at ~1.69
      # Medium (1.0): bounces at ~1.52
      # Large (1.44): bounces at ~1.32
      _(small.velocity_x).must_be_close_to 1.69, 0.1
      _(medium.velocity_x).must_be_close_to 1.52, 0.1
      _(large.velocity_x).must_be_close_to 1.32, 0.1
      # Small bounces most, large bounces least
      _(small.velocity_x).must_be :>, medium.velocity_x
      _(medium.velocity_x).must_be :>, large.velocity_x
    end

    it "reverses velocity direction on bounce" do
      arena = build_arena
      actor = build_actor(x: 10, y: 100)
      actor.velocity_x = -10.0
      actor.velocity_y = 0.0

      Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: arena.width, arena_height: arena.height
      )

      _(actor.velocity_x).must_be :>, 0 # Reversed from negative to positive
    end

    it "only affects the component that hit the wall" do
      arena = build_arena
      actor = build_actor(x: 10, y: 100)
      actor.velocity_x = -10.0
      actor.velocity_y = 5.0

      Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: arena.width, arena_height: arena.height
      )

      _(actor.velocity_x).must_be :>, 0 # Bounced
      _(actor.velocity_y).must_equal 5.0 # Unchanged
    end

    it "handles corner collision affecting both axes" do
      arena = build_arena
      actor = build_actor(x: 10, y: 10)
      actor.velocity_x = -10.0
      actor.velocity_y = -10.0

      Rubowar::CollisionSystem.process_wall_collision(
        actor:, arena_width: arena.width, arena_height: arena.height
      )

      _(actor.velocity_x).must_be :>, 0 # Bounced
      _(actor.velocity_y).must_be :>, 0 # Bounced
    end
  end

  describe "RubotActor#thrust" do
    it "costs less for small rubot at same speed" do
      small_actor = build_actor(x: 100, y: 100, klass: SmallProbeTestBot)
      medium_actor = build_actor(x: 200, y: 100)
      small_actor.energy = 100
      medium_actor.energy = 100

      small_actor.thrust(speed: 3, angle: 0)
      medium_actor.thrust(speed: 3, angle: 0)

      # Small: (3/1.5)² × 0.5625 = 4 × 0.5625 = 2.25
      # Medium: (3/1.5)² × 1.0 = 4 × 1.0 = 4
      _(small_actor.energy).must_be :>, medium_actor.energy
    end

    it "costs more for large rubot at same speed" do
      large_actor = build_actor(x: 100, y: 100, klass: LargeProbeTestBot)
      medium_actor = build_actor(x: 200, y: 100)
      large_actor.energy = 100
      medium_actor.energy = 100

      large_actor.thrust(speed: 3, angle: 0)
      medium_actor.thrust(speed: 3, angle: 0)

      # Large: (3/1.5)² × 1.5625 = 4 × 1.5625 = 6.25
      # Medium: (3/1.5)² × 1.0 = 4 × 1.0 = 4
      _(large_actor.energy).must_be :<, medium_actor.energy
    end

    it "adds velocity in the specified direction" do
      actor = build_actor(x: 100, y: 100)
      actor.energy = 100

      actor.thrust(speed: 5, angle: 0) # East

      _(actor.velocity_x).must_be_close_to 5.0, 0.01
      _(actor.velocity_y).must_be_close_to 0.0, 0.01
    end

    it "applies direction multiplier when thrusting against momentum" do
      actor = build_actor(x: 100, y: 100)
      actor.velocity_x = 5.0 # Moving east
      actor.energy = 100

      actor.thrust(speed: 3, angle: 180) # Thrust west (against)

      # Cost should be 2x: (3/1.5)² × 1.0 × 2.0 = 8
      _(actor.energy).must_be_close_to 92, 0.1
    end

    it "provides partial thrust when energy is insufficient" do
      actor = build_actor(x: 100, y: 100)
      actor.energy = 2 # Not enough for full thrust

      actor.thrust(speed: 5, angle: 0)

      _(actor.energy).must_equal 0
      _(actor.velocity_x).must_be :>, 0
      _(actor.velocity_x).must_be :<, 5
    end
  end

  describe "#find_probe_target" do
    it "returns nil when no other rubots exist" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [actor]

      result = arena.find_probe_target(actor)

      _(result).must_be_nil
    end

    it "returns nil when target is behind the shooter" do
      arena = build_arena
      shooter = build_actor(x: 200, y: 100, turret_angle: 0) # Facing east
      target = build_actor(x: 100, y: 100) # West of shooter
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "returns target when directly in front" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0) # Facing east
      target = build_actor(x: 200, y: 100) # East of shooter
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "returns target when ray passes through radius" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0) # Facing east
      target = build_actor(x: 200, y: 110) # Slightly offset but within radius (20)
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "returns nil when target is outside ray path" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0) # Facing east
      target = build_actor(x: 200, y: 150) # Too far offset (50 > radius of 20)
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "returns closest target when multiple in line" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      near_target = build_actor(x: 200, y: 100)
      far_target = build_actor(x: 400, y: 100)
      arena.actors = [shooter, far_target, near_target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal near_target
    end

    it "ignores dead rubots" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      dead_target = build_actor(x: 200, y: 100)
      dead_target.health = 0
      arena.actors = [shooter, dead_target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "works with angle 90 (north)" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 90) # Facing north
      target = build_actor(x: 100, y: 200) # North of shooter
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "works with angle 180 (west)" do
      arena = build_arena
      shooter = build_actor(x: 200, y: 100, turret_angle: 180) # Facing west
      target = build_actor(x: 100, y: 100) # West of shooter
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "works with angle 270 (south)" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 200, turret_angle: 270) # Facing south
      target = build_actor(x: 100, y: 100) # South of shooter
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "works with diagonal angle 45 (northeast)" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 45)
      target = build_actor(x: 200, y: 200) # Northeast, on the 45° line
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "works with diagonal angle 135 (northwest)" do
      arena = build_arena
      shooter = build_actor(x: 200, y: 100, turret_angle: 135)
      target = build_actor(x: 100, y: 200) # Northwest
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "detects target at edge of radius" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 119) # Offset by 19, just inside radius of 20
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "misses target just outside radius" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 121) # Offset by 21, just outside radius of 20
      arena.actors = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "does not detect self" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [shooter]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "detects small rubot with radius 15" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      small_target = build_actor(x: 200, y: 114, klass: SmallProbeTestBot) # Offset 14, inside radius 15
      arena.actors = [shooter, small_target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal small_target
    end

    it "misses small rubot outside its radius" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      small_target = build_actor(x: 200, y: 117, klass: SmallProbeTestBot) # Offset 17, outside radius 16
      arena.actors = [shooter, small_target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "detects large rubot with radius 24" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      large_target = build_actor(x: 200, y: 123, klass: LargeProbeTestBot) # Offset 23, inside radius 24
      arena.actors = [shooter, large_target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal large_target
    end
  end

  describe "#build_probe_echo" do
    it "returns empty hash with no attributes" do
      arena = build_arena
      target = build_actor(x: 200, y: 150)
      target.velocity_x = 5.0
      target.shield_level = 10
      target.health = 80
      target.energy = 60

      result = arena.build_probe_echo(target:, attributes: [])

      _(result.key?(:x)).must_equal false
      _(result.key?(:y)).must_equal false
      _(result.key?(:size)).must_equal false
      _(result.key?(:velocity_x)).must_equal false
      _(result.key?(:shield_level)).must_equal false
      _(result.key?(:health)).must_equal false
      _(result.key?(:energy)).must_equal false
    end

    it "returns x, y with position attribute" do
      arena = build_arena
      target = build_actor(x: 200, y: 150)

      result = arena.build_probe_echo(target:, attributes: [:position])

      _(result[:x]).must_equal 200
      _(result[:y]).must_equal 150
      _(result.key?(:size)).must_equal false
    end

    it "adds size when requested" do
      arena = build_arena
      target = build_actor(x: 200, y: 150)

      result = arena.build_probe_echo(target:, attributes: [:size])

      _(result[:size]).must_equal :medium
      _(result.key?(:velocity_x)).must_equal false
    end

    it "adds velocity when requested" do
      arena = build_arena
      target = build_actor(x: 200, y: 150)
      target.velocity_x = 5.0
      target.velocity_y = -3.0

      result = arena.build_probe_echo(target:, attributes: [:velocity])

      _(result[:velocity_x]).must_equal 5.0
      _(result[:velocity_y]).must_equal(-3.0)
      _(result.key?(:x)).must_equal false
      _(result.key?(:size)).must_equal false
    end

    it "adds turret_angle when requested" do
      arena = build_arena
      target = build_actor(x: 200, y: 150, turret_angle: 45)

      result = arena.build_probe_echo(target:, attributes: [:turret_angle])

      _(result[:turret_angle]).must_equal 45
      _(result.key?(:x)).must_equal false
    end

    it "adds shield_level when requested" do
      arena = build_arena
      target = build_actor(x: 200, y: 150)
      target.shield_level = 25

      result = arena.build_probe_echo(target:, attributes: [:shield])

      _(result[:shield_level]).must_equal 25
      _(result.key?(:health)).must_equal false
    end

    it "adds health when requested" do
      arena = build_arena
      target = build_actor(x: 200, y: 150)
      target.health = 75

      result = arena.build_probe_echo(target:, attributes: [:health])

      _(result[:health]).must_equal 75
      _(result.key?(:energy)).must_equal false
    end

    it "adds energy when requested" do
      arena = build_arena
      target = build_actor(x: 200, y: 150)
      target.energy = 45

      result = arena.build_probe_echo(target:, attributes: [:energy])

      _(result[:energy]).must_equal 45
    end

    it "adds multiple attributes when requested" do
      arena = build_arena
      target = build_actor(x: 200, y: 150)
      target.velocity_x = 5.0
      target.velocity_y = -3.0
      target.health = 75

      result = arena.build_probe_echo(target:, attributes: %i[position velocity health])

      _(result[:x]).must_equal 200
      _(result[:y]).must_equal 150
      _(result[:velocity_x]).must_equal 5.0
      _(result[:velocity_y]).must_equal(-3.0)
      _(result[:health]).must_equal 75
      _(result.key?(:size)).must_equal false
      _(result.key?(:shield_level)).must_equal false
      _(result.key?(:energy)).must_equal false
    end
  end

  describe "#process_probe" do
    it "sets probe result on rubot instance when target found" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 100)
      arena.actors = [shooter, target]

      arena.process_probe(actor: shooter, attributes: [:position])

      result = shooter.instance.probe_echo
      _(result).wont_be_nil
      _(result[:x]).must_equal 200
    end

    it "sets probe result to empty ProbeEcho when no target found" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [shooter]

      arena.process_probe(actor: shooter, attributes: [:size])

      result = shooter.instance.probe_echo
      _(result).must_be :empty?
    end

    it "spends zero energy with no attributes" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 50
      arena.actors = [shooter]

      arena.process_probe(actor: shooter, attributes: [])

      _(shooter.energy).must_equal 50
    end

    it "spends 1 energy for size attribute" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 50
      arena.actors = [shooter]

      arena.process_probe(actor: shooter, attributes: [:size])

      _(shooter.energy).must_equal 49
    end

    it "spends energy based on requested attributes" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 50
      arena.actors = [shooter]

      arena.process_probe(actor: shooter, attributes: %i[size velocity])

      _(shooter.energy).must_equal 46 # 50 - 1 (size) - 3 (velocity)
    end

    it "spends full cost for all attributes" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 50
      arena.actors = [shooter]

      arena.process_probe(actor: shooter, attributes: %i[size position velocity shield health energy])

      _(shooter.energy).must_equal 34 # 50 - 1 - 4 - 3 - 2 - 3 - 3 = 34
    end

    it "returns false and drains energy when insufficient" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 2
      arena.actors = [shooter]

      result = arena.process_probe(actor: shooter, attributes: [:health]) # costs 3 (health only)

      _(result).must_equal false
      _(shooter.energy).must_equal 0
    end

    it "updates probe result when target moves out of sight" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 100)
      arena.actors = [shooter, target]

      arena.process_probe(actor: shooter, attributes: [:size])
      first_result = shooter.instance.probe_echo
      _(first_result).wont_be_empty

      target.y = 200
      arena.process_probe(actor: shooter, attributes: [:size])
      second_result = shooter.instance.probe_echo

      _(second_result).must_be_empty
    end

    it "updates probe result when new target appears" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [shooter]

      arena.process_probe(actor: shooter, attributes: [:position])
      first_result = shooter.instance.probe_echo
      _(first_result).must_be_empty

      target = build_actor(x: 200, y: 100)
      arena.actors = [shooter, target]
      arena.process_probe(actor: shooter, attributes: [:position])
      second_result = shooter.instance.probe_echo

      _(second_result).wont_be_empty
      _(second_result[:x]).must_equal 200
    end

    it "returns size only when requested" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      small_target = build_actor(x: 200, y: 100, klass: SmallProbeTestBot)
      arena.actors = [shooter, small_target]

      arena.process_probe(actor: shooter, attributes: [:size])
      result = shooter.instance.probe_echo

      _(result[:size]).must_equal :small
    end

    it "does not return size when not requested" do
      arena = build_arena
      shooter = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 100)
      arena.actors = [shooter, target]

      arena.process_probe(actor: shooter, attributes: [])
      result = shooter.instance.probe_echo

      _(result.size).must_be_nil
    end
  end

  describe "#in_arc?" do
    it "returns true for target directly in front within distance" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 200, x: 200, y: 100)

      _(result).must_equal true
    end

    it "returns false for target beyond max distance" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 50, x: 200, y: 100)

      _(result).must_equal false
    end

    it "returns true for target within arc angle" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      # Target at 10 degrees, arc is 30 degrees (±15)
      target_x = 100 + (100 * Math.cos(10 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(10 * Math::PI / 180))

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal true
    end

    it "returns false for target outside arc angle" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      # Target at 45 degrees, arc is 30 degrees (±15)
      target_x = 100 + (100 * Math.cos(45 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(45 * Math::PI / 180))

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal false
    end

    it "handles turret angle 90 (north)" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 90)

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 200, x: 100, y: 200)

      _(result).must_equal true
    end

    it "handles turret angle 180 (west)" do
      arena = build_arena
      scanner = build_actor(x: 200, y: 100, turret_angle: 180)

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 200, x: 100, y: 100)

      _(result).must_equal true
    end

    it "handles turret angle 270 (south)" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 200, turret_angle: 270)

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 200, x: 100, y: 100)

      _(result).must_equal true
    end

    it "returns true at edge of arc angle" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      # Target at exactly 15 degrees, arc is 30 degrees (±15)
      target_x = 100 + (100 * Math.cos(15 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(15 * Math::PI / 180))

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal true
    end

    it "returns false just outside arc angle" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      # Target at 16 degrees, arc is 30 degrees (±15)
      target_x = 100 + (100 * Math.cos(16 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(16 * Math::PI / 180))

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal false
    end

    it "handles negative arc angles (behind turret direction)" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      # Target at -10 degrees
      target_x = 100 + (100 * Math.cos(-10 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(-10 * Math::PI / 180))

      result = arena.in_arc?(actor: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal true
    end

    it "handles wraparound at 360 degrees" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 350)
      # Target at 10 degrees (20 degree difference across 0)
      target_x = 100 + (100 * Math.cos(10 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(10 * Math::PI / 180))

      result = arena.in_arc?(actor: scanner, angle: 60, distance: 200, x: target_x, y: target_y)

      _(result).must_equal true
    end
  end

  describe "#process_scan" do
    it "calculates correct energy cost for base scan" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 100
      arena.actors = [scanner]

      arena.process_scan(actor: scanner, angle: 20, distance: 100, velocity: false, owner: false)

      # Cost: 3 base + ceil(20/20) + ceil(100/100) = 3 + 1 + 1 = 5
      _(scanner.energy).must_equal 95
    end

    it "calculates correct energy cost with velocity" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 100
      arena.actors = [scanner]

      arena.process_scan(actor: scanner, angle: 20, distance: 100, velocity: true, owner: false)

      # Cost: 3 base + 1 + 1 + 2 velocity = 7
      _(scanner.energy).must_equal 93
    end

    it "calculates correct cost for large scan area" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 100
      arena.actors = [scanner]

      arena.process_scan(actor: scanner, angle: 90, distance: 300, velocity: false, owner: false)

      # Cost: 3 base + ceil(90/20) + ceil(300/100) = 3 + 5 + 3 = 11
      _(scanner.energy).must_equal 89
    end

    it "returns empty ScanEcho when no targets in arc" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 100, y: 300) # North, not in east-facing arc
      arena.actors = [scanner, target]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_echo

      _(result).must_be :empty?
    end

    it "returns rubot in arc" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 100)
      arena.actors = [scanner, target]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_echo

      _(result.length).must_equal 1
      _(result[0][:x]).must_equal 200
      _(result[0][:y]).must_equal 100
      _(result[0][:type]).must_equal :rubot
    end

    it "returns multiple rubots in arc" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      target1 = build_actor(x: 200, y: 100)
      target2 = build_actor(x: 250, y: 110)
      arena.actors = [scanner, target1, target2]

      arena.process_scan(actor: scanner, angle: 30, distance: 300, velocity: false, owner: false)
      result = scanner.instance.scan_echo

      _(result.length).must_equal 2
      _(result.all? { |r| r[:type] == :rubot }).must_equal true
    end

    it "does not include self in results" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      arena.actors = [scanner]

      arena.process_scan(actor: scanner, angle: 360, distance: 500, velocity: false, owner: false)
      result = scanner.instance.scan_echo

      _(result).must_be :empty?
    end

    it "does not include dead rubots" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      dead_target = build_actor(x: 200, y: 100)
      dead_target.health = 0
      arena.actors = [scanner, dead_target]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_echo

      _(result).must_be :empty?
    end

    it "includes velocity when requested" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 100)
      target.velocity_x = 5.0
      target.velocity_y = -3.0
      arena.actors = [scanner, target]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: true, owner: false)
      result = scanner.instance.scan_echo

      _(result[0][:velocity_x]).must_equal 5.0
      _(result[0][:velocity_y]).must_equal(-3.0)
    end

    it "does not include velocity when not requested" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 100)
      target.velocity_x = 5.0
      arena.actors = [scanner, target]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_echo

      _(result[0].velocity_x).must_be_nil
    end

    it "detects bullets in arc" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      bullet = Rubowar::Bullet.new(x: 200, y: 100, angle: 180, damage: 10, owner: scanner)
      arena.actors = [scanner]
      arena.bullets = [bullet]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_echo

      _(result.length).must_equal 1
      _(result[0][:type]).must_equal :bullet
    end

    it "includes bullet velocity when requested" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      bullet = Rubowar::Bullet.new(x: 200, y: 100, angle: 180, damage: 10, owner: scanner)
      arena.actors = [scanner]
      arena.bullets = [bullet]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: true, owner: false)
      result = scanner.instance.scan_echo

      _(result[0].velocity_x).wont_be_nil
      _(result[0].velocity_y).wont_be_nil
    end

    it "returns both rubots and bullets in arc" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 100)
      bullet = Rubowar::Bullet.new(x: 250, y: 100, angle: 180, damage: 10, owner: scanner)
      arena.actors = [scanner, target]
      arena.bullets = [bullet]

      arena.process_scan(actor: scanner, angle: 30, distance: 300, velocity: false, owner: false)
      result = scanner.instance.scan_echo

      _(result.length).must_equal 2
      types = result.map { |r| r[:type] }
      _(types).must_include :rubot
      _(types).must_include :bullet
    end

    it "returns false and drains energy when insufficient" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 3
      arena.actors = [scanner]

      result = arena.process_scan(actor: scanner, angle: 20, distance: 100, velocity: false, owner: false)

      _(result).must_equal false
      _(scanner.energy).must_equal 0
    end

    it "adds owner cost when owner option is true" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 100
      arena.actors = [scanner]

      arena.process_scan(actor: scanner, angle: 20, distance: 100, velocity: false, owner: true)

      # Cost: 3 base + 1 angle + 1 distance + 1 owner = 6
      _(scanner.energy).must_equal 94
    end

    it "includes owner info for bullets when requested" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      shooter = build_actor(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 200, y: 100, angle: 180, damage: 10, owner: shooter)
      arena.actors = [scanner, shooter]
      arena.bullets = [bullet]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: false, owner: true)
      result = scanner.instance.scan_echo

      bullet_result = result.find { |r| r[:type] == :bullet }
      _(bullet_result[:owner]).must_equal "ProbeTestBot"
    end

    it "sets owner to nil for rubots when owner requested" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      target = build_actor(x: 200, y: 100)
      arena.actors = [scanner, target]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: false, owner: true)
      result = scanner.instance.scan_echo

      _(result[0][:owner]).must_be_nil
    end

    it "does not include owner when not requested" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      shooter = build_actor(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 200, y: 100, angle: 180, damage: 10, owner: shooter)
      arena.actors = [scanner, shooter]
      arena.bullets = [bullet]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_echo

      bullet_result = result.find { |r| r[:type] == :bullet }
      # When owner is not requested, the owner field is nil
      _(bullet_result.owner).must_be_nil
    end

    it "handles bullet with nil owner (dead rubot)" do
      arena = build_arena
      scanner = build_actor(x: 100, y: 100, turret_angle: 0)
      bullet = Rubowar::Bullet.new(x: 200, y: 100, angle: 180, damage: 10, owner: nil)
      arena.actors = [scanner]
      arena.bullets = [bullet]

      arena.process_scan(actor: scanner, angle: 30, distance: 200, velocity: false, owner: true)
      result = scanner.instance.scan_echo

      bullet_result = result.find { |r| r[:type] == :bullet }
      _(bullet_result[:owner]).must_be_nil
    end
  end

  describe "#within_distance?" do
    it "returns true for target within distance" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)

      result = arena.within_distance?(actor:, distance: 150, x: 200, y: 100)

      _(result).must_equal true
    end

    it "returns false for target beyond distance" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)

      result = arena.within_distance?(actor:, distance: 50, x: 200, y: 100)

      _(result).must_equal false
    end

    it "returns true at exact distance" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)

      result = arena.within_distance?(actor:, distance: 100, x: 200, y: 100)

      _(result).must_equal true
    end

    it "works in all directions" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)

      # North
      _(arena.within_distance?(actor:, distance: 100, x: 100, y: 200)).must_equal true
      # South
      _(arena.within_distance?(actor:, distance: 100, x: 100, y: 0)).must_equal true
      # East
      _(arena.within_distance?(actor:, distance: 100, x: 200, y: 100)).must_equal true
      # West
      _(arena.within_distance?(actor:, distance: 100, x: 0, y: 100)).must_equal true
    end
  end

  describe "#process_pulse" do
    it "calculates correct energy cost" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.energy = 100
      arena.actors = [actor]

      arena.process_pulse(actor:, distance: 75, owner: false)

      # Cost: 2 base + ceil(75/75) = 2 + 1 = 3
      _(actor.energy).must_equal 97
    end

    it "calculates correct cost for longer distance" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.energy = 100
      arena.actors = [actor]

      arena.process_pulse(actor:, distance: 200, owner: false)

      # Cost: 2 base + ceil(200/75) = 2 + 3 = 5
      _(actor.energy).must_equal 95
    end

    it "returns empty PulseEcho when no targets in range" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      target = build_actor(x: 500, y: 500) # Far away
      arena.actors = [actor, target]

      arena.process_pulse(actor:, distance: 100, owner: false)
      result = actor.instance.pulse_echo

      _(result).must_be :empty?
    end

    it "returns rubot in range" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      target = build_actor(x: 150, y: 100) # 50 units away
      arena.actors = [actor, target]

      arena.process_pulse(actor:, distance: 100, owner: false)
      result = actor.instance.pulse_echo

      _(result.length).must_equal 1
      _(result[0][:x]).must_equal 150
      _(result[0][:y]).must_equal 100
      _(result[0][:type]).must_equal :rubot
    end

    it "returns multiple rubots in range" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      target1 = build_actor(x: 150, y: 100)
      target2 = build_actor(x: 100, y: 150)
      arena.actors = [actor, target1, target2]

      arena.process_pulse(actor:, distance: 100, owner: false)
      result = actor.instance.pulse_echo

      _(result.length).must_equal 2
      _(result.all? { |r| r[:type] == :rubot }).must_equal true
    end

    it "does not include self in results" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      arena.actors = [actor]

      arena.process_pulse(actor:, distance: 500, owner: false)
      result = actor.instance.pulse_echo

      _(result).must_be :empty?
    end

    it "does not include dead rubots" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      dead_target = build_actor(x: 150, y: 100)
      dead_target.health = 0
      arena.actors = [actor, dead_target]

      arena.process_pulse(actor:, distance: 100, owner: false)
      result = actor.instance.pulse_echo

      _(result).must_be :empty?
    end

    it "detects bullets in range" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 150, y: 100, angle: 180, damage: 10, owner: actor)
      arena.actors = [actor]
      arena.bullets = [bullet]

      arena.process_pulse(actor:, distance: 100, owner: false)
      result = actor.instance.pulse_echo

      _(result.length).must_equal 1
      _(result[0][:type]).must_equal :bullet
    end

    it "returns both rubots and bullets in range" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      target = build_actor(x: 150, y: 100)
      bullet = Rubowar::Bullet.new(x: 100, y: 150, angle: 180, damage: 10, owner: actor)
      arena.actors = [actor, target]
      arena.bullets = [bullet]

      arena.process_pulse(actor:, distance: 100, owner: false)
      result = actor.instance.pulse_echo

      _(result.length).must_equal 2
      types = result.map { |r| r[:type] }
      _(types).must_include :rubot
      _(types).must_include :bullet
    end

    it "does not include velocity data" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      target = build_actor(x: 150, y: 100)
      target.velocity_x = 5.0
      target.velocity_y = -3.0
      arena.actors = [actor, target]

      arena.process_pulse(actor:, distance: 100, owner: false)
      result = actor.instance.pulse_echo

      _(result[0].velocity_x).must_be_nil
      _(result[0].velocity_y).must_be_nil
    end

    it "returns false and drains energy when insufficient" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.energy = 2
      arena.actors = [actor]

      result = arena.process_pulse(actor:, distance: 75, owner: false)

      _(result).must_equal false
      _(actor.energy).must_equal 0
    end

    it "detects targets in all directions" do
      arena = build_arena
      actor = build_actor(x: 200, y: 200)
      north = build_actor(x: 200, y: 250)
      south = build_actor(x: 200, y: 150)
      east = build_actor(x: 250, y: 200)
      west = build_actor(x: 150, y: 200)
      arena.actors = [actor, north, south, east, west]

      arena.process_pulse(actor:, distance: 100, owner: false)
      result = actor.instance.pulse_echo

      _(result.length).must_equal 4
    end

    it "adds owner cost when owner option is true" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.energy = 100
      arena.actors = [actor]

      arena.process_pulse(actor:, distance: 75, owner: true)

      # Cost: 2 base + 1 distance + 1 owner = 4
      _(actor.energy).must_equal 96
    end

    it "includes owner info for bullets when requested" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      shooter = build_actor(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 150, y: 100, angle: 180, damage: 10, owner: shooter)
      arena.actors = [actor, shooter]
      arena.bullets = [bullet]

      arena.process_pulse(actor:, distance: 100, owner: true)
      result = actor.instance.pulse_echo

      bullet_result = result.find { |r| r[:type] == :bullet }
      _(bullet_result[:owner]).must_equal "ProbeTestBot"
    end

    it "sets owner to nil for rubots when owner requested" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      target = build_actor(x: 150, y: 100)
      arena.actors = [actor, target]

      arena.process_pulse(actor:, distance: 100, owner: true)
      result = actor.instance.pulse_echo

      _(result[0][:owner]).must_be_nil
    end

    it "does not include owner when not requested" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      shooter = build_actor(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 150, y: 100, angle: 180, damage: 10, owner: shooter)
      arena.actors = [actor, shooter]
      arena.bullets = [bullet]

      arena.process_pulse(actor:, distance: 100, owner: false)
      result = actor.instance.pulse_echo

      bullet_result = result.find { |r| r[:type] == :bullet }
      # When owner is not requested, the owner field is nil
      _(bullet_result.owner).must_be_nil
    end

    it "handles bullet with nil owner (dead rubot)" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 150, y: 100, angle: 180, damage: 10, owner: nil)
      arena.actors = [actor]
      arena.bullets = [bullet]

      arena.process_pulse(actor:, distance: 100, owner: true)
      result = actor.instance.pulse_echo

      bullet_result = result.find { |r| r[:type] == :bullet }
      _(bullet_result[:owner]).must_be_nil
    end
  end

  describe "#spawn_energon" do
    it "creates an energon in the arena" do
      arena = build_arena
      arena.actors = []

      energon = arena.spawn_energon(100)

      _(energon).must_be_instance_of Rubowar::Energon
      _(arena.energons.length).must_equal 1
    end

    it "spawns at center when no rubots exist" do
      arena = build_arena
      arena.actors = []

      energon = arena.spawn_energon(100)

      _(energon.x).must_equal arena.width / 2.0
      _(energon.y).must_equal arena.height / 2.0
    end

    it "spawns away from rubots" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      arena.actors = [actor]

      energon = arena.spawn_energon(100)

      distance = Math.sqrt(((energon.x - actor.x)**2) + ((energon.y - actor.y)**2))
      _(distance).must_be :>, 50 # Should spawn away from rubot
    end

    it "records spawn chronon" do
      arena = build_arena
      arena.actors = []

      energon = arena.spawn_energon(150)

      _(energon.spawn_chronon).must_equal 150
    end

    it "maximizes minimum distance from all rubots" do
      arena = build_arena
      actor1 = build_actor(x: 200, y: 200)
      actor2 = build_actor(x: 600, y: 400)
      arena.actors = [actor1, actor2]

      energon = arena.spawn_energon(100)

      # Energon should be positioned to maximize distance from nearest rubot
      dist1 = Math.sqrt(((energon.x - actor1.x)**2) + ((energon.y - actor1.y)**2))
      dist2 = Math.sqrt(((energon.x - actor2.x)**2) + ((energon.y - actor2.y)**2))
      min_dist = [dist1, dist2].min

      # Should be reasonably far from both (not right next to either)
      _(min_dist).must_be :>, 100
    end

    it "respects wall buffer" do
      arena = build_arena
      arena.actors = []
      wall_buffer = (arena.height * Rubowar::Config::Arena::ENERGON_WALL_BUFFER_RATIO).round

      energon = arena.spawn_energon(100)

      _(energon.x).must_be :>=, wall_buffer
      _(energon.x).must_be :<=, arena.width - wall_buffer
      _(energon.y).must_be :>=, wall_buffer
      _(energon.y).must_be :<=, arena.height - wall_buffer
    end
  end

  describe "#check_energon_collection" do
    it "returns empty array when no energons exist" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      arena.actors = [actor]

      collections = arena.check_energon_collection(100)

      _(collections).must_equal []
    end

    it "returns empty array when rubot not touching energon" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      arena.actors = [actor]
      energon = Rubowar::Energon.spawn(x: 500, y: 500, spawn_chronon: 50)
      arena.energons = [energon]

      collections = arena.check_energon_collection(100)

      _(collections).must_equal []
    end

    it "collects energon when rubot overlaps" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      arena.actors = [actor]
      # Place energon within collection range (rubot radius + energon radius)
      energon = Rubowar::Energon.spawn(x: 100 + actor.radius, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      collections = arena.check_energon_collection(100)

      _(collections.length).must_equal 1
      _(collections[0][:actor]).must_equal actor
      _(collections[0][:energon]).must_equal energon
    end

    it "removes collected energon from arena" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      arena.actors = [actor]
      energon = Rubowar::Energon.spawn(x: 100, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      arena.check_energon_collection(100)

      _(arena.energons).must_be_empty
    end

    it "adds energy to collecting rubot" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.energy = 50
      arena.actors = [actor]
      energon = Rubowar::Energon.spawn(x: 100, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      arena.check_energon_collection(100)

      _(actor.energy).must_be :>, 50
    end

    it "caps energy at max" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.energy = actor.max_energy - 1
      arena.actors = [actor]
      energon = Rubowar::Energon.spawn(x: 100, y: 100, spawn_chronon: 0)
      arena.energons = [energon]

      arena.check_energon_collection(100) # 100 chronons old = 101 value

      _(actor.energy).must_equal actor.max_energy
    end

    it "ignores dead rubots" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.health = 0
      arena.actors = [actor]
      energon = Rubowar::Energon.spawn(x: 100, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      collections = arena.check_energon_collection(100)

      _(collections).must_be_empty
      _(arena.energons.length).must_equal 1
    end

    it "returns collection amount based on energon value" do
      arena = build_arena
      actor = build_actor(x: 100, y: 100)
      actor.energy = 0
      arena.actors = [actor]
      energon = Rubowar::Energon.spawn(x: 100, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      collections = arena.check_energon_collection(100) # 50 chronons old

      expected_value = energon.value_int(100)
      _(collections[0][:amount]).must_equal expected_value
    end
  end
end
