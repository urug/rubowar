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

def build_arena
  Rubowar::Arena.new(width: 800, height: 600)
end

def build_runner(x:, y:, turret_angle: 0, klass: ProbeTestBot)
  runner = Rubowar::RubotActor.new(klass)
  runner.x = x
  runner.y = y
  runner.turret_angle = turret_angle
  runner
end

describe Rubowar::Arena do
  describe "initialization" do
    it "sets width and height" do
      arena = Rubowar::Arena.new(width: 1000, height: 800)

      _(arena.width).must_equal 1000
      _(arena.height).must_equal 800
    end

    it "uses default values" do
      arena = Rubowar::Arena.new

      _(arena.width).must_equal Rubowar::Config::Arena::DEFAULT_WIDTH
      _(arena.height).must_equal Rubowar::Config::Arena::DEFAULT_HEIGHT
      _(arena.friction).must_equal Rubowar::Config::Arena::DEFAULT_FRICTION
    end

    it "starts with empty bullets and runners" do
      arena = Rubowar::Arena.new

      _(arena.bullets).must_equal []
      _(arena.runners).must_equal []
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
    it "creates runners from rubot classes" do
      arena = build_arena

      arena.spawn_rubots([ProbeTestBot, SmallProbeTestBot])

      _(arena.runners.length).must_equal 2
      _(arena.runners[0].instance).must_be_instance_of ProbeTestBot
      _(arena.runners[1].instance).must_be_instance_of SmallProbeTestBot
    end

    it "positions runners within arena bounds" do
      arena = build_arena

      arena.spawn_rubots([ProbeTestBot, ProbeTestBot])

      arena.runners.each do |runner|
        _(runner.x).must_be :>, runner.radius
        _(runner.x).must_be :<, arena.width - runner.radius
        _(runner.y).must_be :>, runner.radius
        _(runner.y).must_be :<, arena.height - runner.radius
      end
    end

    it "sets random turret angles" do
      arena = build_arena

      arena.spawn_rubots([ProbeTestBot])

      _(arena.runners[0].turret_angle).must_be :>=, 0
      _(arena.runners[0].turret_angle).must_be :<, 360
    end
  end

  describe "#to_state" do
    it "returns ArenaState with current values" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      arena.runners = [runner]

      state = arena.to_state(50)

      _(state).must_be_instance_of Rubowar::ArenaState
      _(state.arena_width).must_equal 800
      _(state.arena_height).must_equal 600
      _(state.chronons).must_equal 50
      _(state.live_rubot_count).must_equal 1
    end

    it "converts energons to hash format" do
      arena = build_arena
      energon = Rubowar::Energon.new(x: 200.0, y: 300.0, spawn_chronon: 10)
      arena.energons = [energon]

      state = arena.to_state(50)

      _(state.energons).must_equal [{ x: 200.0, y: 300.0 }]
    end
  end

  describe "#regenerate_and_degrade" do
    it "regenerates energy for alive runners" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.energy = 50
      arena.runners = [runner]

      arena.regenerate_and_degrade

      _(runner.energy).must_equal 60
    end

    it "degrades shields for alive runners" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.shield_level = 100
      arena.runners = [runner]

      arena.regenerate_and_degrade

      _(runner.shield_level).must_equal 88
    end

    it "skips dead runners" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.health = 0
      runner.energy = 50
      arena.runners = [runner]

      arena.regenerate_and_degrade

      _(runner.energy).must_equal 50
    end
  end

  describe "#process_action" do
    it "processes thrust action" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      arena.runners = [runner]

      result = arena.process_action(runner:, action: { type: :thrust, speed: 3, angle: 0 })

      _(result).must_equal true
      _(runner.velocity_x).must_be :>, 0
    end

    it "processes turret action" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.runners = [runner]

      result = arena.process_action(runner:, action: { type: :rotate_turret, degrees: 45 })

      _(result).must_equal true
      _(runner.turret_angle).must_equal 45.0
    end

    it "processes fire action" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.runners = [runner]

      result = arena.process_action(runner:, action: { type: :fire, energy: 10 })

      _(result).must_equal true
      _(arena.bullets.length).must_equal 1
    end

    it "processes shield action" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      arena.runners = [runner]

      result = arena.process_action(runner:, action: { type: :shield, energy: 20 })

      _(result).must_equal true
      _(runner.shield_level).must_equal 20
    end

    it "returns false for unknown action" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)

      result = arena.process_action(runner:, action: { type: :unknown })

      _(result).must_equal false
    end
  end

  describe "#process_fire" do
    it "creates bullet at turret position" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.runners = [runner]

      arena.process_fire(runner:, energy: 10)

      _(arena.bullets.length).must_equal 1
      bullet = arena.bullets.first
      _(bullet.x).must_be :>, runner.x
    end

    it "calculates damage from energy" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.runners = [runner]

      arena.process_fire(runner:, energy: 10)

      bullet = arena.bullets.first
      expected_damage = (10 * Rubowar::Config::Combat::FIRE_DAMAGE_MULTIPLIER).ceil
      _(bullet.damage).must_equal expected_damage
    end

    it "spends energy" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100, turret_angle: 0)
      runner.energy = 50
      arena.runners = [runner]

      arena.process_fire(runner:, energy: 10)

      _(runner.energy).must_equal 40
    end

    it "returns false when insufficient energy" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100, turret_angle: 0)
      runner.energy = 5
      arena.runners = [runner]

      result = arena.process_fire(runner:, energy: 10)

      _(result).must_equal false
      _(arena.bullets).must_be_empty
    end
  end

  describe "#check_bullet_hit" do
    it "returns true when bullet hits runner" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      shooter = build_runner(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: shooter)
      arena.runners = [runner, shooter]

      result = arena.check_bullet_hit(bullet)

      _(result).must_equal true
    end

    it "applies damage to hit runner" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      shooter = build_runner(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: shooter)
      initial_health = runner.health
      arena.runners = [runner, shooter]

      arena.check_bullet_hit(bullet)

      _(runner.health).must_equal initial_health - 15
    end

    it "tracks damage dealt for shooter" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      shooter = build_runner(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: shooter)
      arena.runners = [runner, shooter]

      arena.check_bullet_hit(bullet)

      _(shooter.damage_dealt).must_equal 15
    end

    it "does not track self-damage" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: runner)
      arena.runners = [runner]

      arena.check_bullet_hit(bullet)

      _(runner.damage_dealt).must_equal 0
    end

    it "returns false when bullet misses" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 500, y: 500, angle: 0, damage: 15, owner: runner)
      arena.runners = [runner]

      result = arena.check_bullet_hit(bullet)

      _(result).must_equal false
    end

    it "ignores dead runners" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.health = 0
      shooter = build_runner(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 15, owner: shooter)
      arena.runners = [runner, shooter]

      result = arena.check_bullet_hit(bullet)

      _(result).must_equal false
    end
  end

  describe "#check_rubot_collisions" do
    it "separates overlapping runners" do
      arena = build_arena
      runner_a = build_runner(x: 100, y: 100)
      runner_b = build_runner(x: 110, y: 100) # Overlapping (distance < sum of radii)
      arena.runners = [runner_a, runner_b]

      arena.check_rubot_collisions

      distance = Math.sqrt(((runner_a.x - runner_b.x)**2) + ((runner_a.y - runner_b.y)**2))
      _(distance).must_be :>=, runner_a.radius + runner_b.radius - 1
    end

    it "applies collision damage" do
      arena = build_arena
      runner_a = build_runner(x: 100, y: 100)
      runner_b = build_runner(x: 110, y: 100)
      runner_a.velocity_x = 5.0
      runner_b.velocity_x = -5.0
      initial_health_a = runner_a.health
      initial_health_b = runner_b.health
      arena.runners = [runner_a, runner_b]

      arena.check_rubot_collisions

      _(runner_a.health).must_be :<, initial_health_a
      _(runner_b.health).must_be :<, initial_health_b
    end

    it "ignores dead runners" do
      arena = build_arena
      runner_a = build_runner(x: 100, y: 100)
      runner_b = build_runner(x: 110, y: 100)
      runner_a.health = 0
      initial_health_b = runner_b.health
      arena.runners = [runner_a, runner_b]

      arena.check_rubot_collisions

      _(runner_b.health).must_equal initial_health_b
    end
  end

  describe "#update_rubot_physics" do
    it "applies friction to runners" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.velocity_x = 10.0
      runner.velocity_y = 0.0
      arena.runners = [runner]

      arena.update_rubot_physics

      _(runner.velocity_x).must_be :<, 10.0
    end

    it "moves runners" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.velocity_x = 10.0
      runner.velocity_y = 0.0
      arena.runners = [runner]

      arena.update_rubot_physics

      _(runner.x).must_be :>, 100.0
    end

    it "skips dead runners" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.velocity_x = 10.0
      runner.health = 0
      arena.runners = [runner]

      arena.update_rubot_physics

      _(runner.x).must_equal 100.0
    end
  end

  describe "#update_bullets" do
    it "moves bullets" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 200, y: 200, angle: 0, damage: 10, owner: runner)
      arena.runners = [runner]
      arena.bullets = [bullet]

      arena.update_bullets

      _(bullet.x).must_be :>, 200
    end

    it "removes bullets that hit runners" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      shooter = build_runner(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 10, owner: shooter)
      arena.runners = [runner, shooter]
      arena.bullets = [bullet]

      arena.update_bullets

      _(arena.bullets).must_be_empty
    end

    it "removes bullets that leave arena" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 850, y: 200, angle: 0, damage: 10, owner: runner)
      arena.runners = [runner]
      arena.bullets = [bullet]

      arena.update_bullets

      _(arena.bullets).must_be_empty
    end
  end

  describe "#check_wall_collision" do
    it "bounces more for small bots and less for large bots" do
      arena = build_arena
      small = build_runner(x: 10, y: 100, klass: SmallProbeTestBot)
      medium = build_runner(x: 10, y: 200)
      large = build_runner(x: 10, y: 300, klass: LargeProbeTestBot)
      [small, medium, large].each do |runner|
        runner.velocity_x = -10.0
        runner.velocity_y = 0.0
      end
      arena.runners = [small, medium, large]

      [small, medium, large].each { |r| arena.check_wall_collision(r) }

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
      runner = build_runner(x: 10, y: 100)
      runner.velocity_x = -10.0
      runner.velocity_y = 0.0
      arena.runners = [runner]

      arena.check_wall_collision(runner)

      _(runner.velocity_x).must_be :>, 0 # Reversed from negative to positive
    end

    it "only affects the component that hit the wall" do
      arena = build_arena
      runner = build_runner(x: 10, y: 100)
      runner.velocity_x = -10.0
      runner.velocity_y = 5.0
      arena.runners = [runner]

      arena.check_wall_collision(runner)

      _(runner.velocity_x).must_be :>, 0 # Bounced
      _(runner.velocity_y).must_equal 5.0 # Unchanged
    end

    it "handles corner collision affecting both axes" do
      arena = build_arena
      runner = build_runner(x: 10, y: 10)
      runner.velocity_x = -10.0
      runner.velocity_y = -10.0
      arena.runners = [runner]

      arena.check_wall_collision(runner)

      _(runner.velocity_x).must_be :>, 0 # Bounced
      _(runner.velocity_y).must_be :>, 0 # Bounced
    end
  end

  describe "RubotActor#thrust" do
    it "costs less for small rubot at same speed" do
      small_runner = build_runner(x: 100, y: 100, klass: SmallProbeTestBot)
      medium_runner = build_runner(x: 200, y: 100)
      small_runner.energy = 100
      medium_runner.energy = 100

      small_runner.thrust(speed: 3, angle: 0)
      medium_runner.thrust(speed: 3, angle: 0)

      # Small: (3/1.5)² × 0.5625 = 4 × 0.5625 = 2.25
      # Medium: (3/1.5)² × 1.0 = 4 × 1.0 = 4
      _(small_runner.energy).must_be :>, medium_runner.energy
    end

    it "costs more for large rubot at same speed" do
      large_runner = build_runner(x: 100, y: 100, klass: LargeProbeTestBot)
      medium_runner = build_runner(x: 200, y: 100)
      large_runner.energy = 100
      medium_runner.energy = 100

      large_runner.thrust(speed: 3, angle: 0)
      medium_runner.thrust(speed: 3, angle: 0)

      # Large: (3/1.5)² × 1.5625 = 4 × 1.5625 = 6.25
      # Medium: (3/1.5)² × 1.0 = 4 × 1.0 = 4
      _(large_runner.energy).must_be :<, medium_runner.energy
    end

    it "adds velocity in the specified direction" do
      runner = build_runner(x: 100, y: 100)
      runner.energy = 100

      runner.thrust(speed: 5, angle: 0) # East

      _(runner.velocity_x).must_be_close_to 5.0, 0.01
      _(runner.velocity_y).must_be_close_to 0.0, 0.01
    end

    it "applies direction multiplier when thrusting against momentum" do
      runner = build_runner(x: 100, y: 100)
      runner.velocity_x = 5.0 # Moving east
      runner.energy = 100

      runner.thrust(speed: 3, angle: 180) # Thrust west (against)

      # Cost should be 2x: (3/1.5)² × 1.0 × 2.0 = 8
      _(runner.energy).must_be_close_to 92, 0.1
    end

    it "provides partial thrust when energy is insufficient" do
      runner = build_runner(x: 100, y: 100)
      runner.energy = 2 # Not enough for full thrust

      runner.thrust(speed: 5, angle: 0)

      _(runner.energy).must_equal 0
      _(runner.velocity_x).must_be :>, 0
      _(runner.velocity_x).must_be :<, 5
    end
  end

  describe "#find_probe_target" do
    it "returns nil when no other rubots exist" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.runners = [runner]

      result = arena.find_probe_target(runner)

      _(result).must_be_nil
    end

    it "returns nil when target is behind the shooter" do
      arena = build_arena
      shooter = build_runner(x: 200, y: 100, turret_angle: 0) # Facing east
      target = build_runner(x: 100, y: 100) # West of shooter
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "returns target when directly in front" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0) # Facing east
      target = build_runner(x: 200, y: 100) # East of shooter
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "returns target when ray passes through radius" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0) # Facing east
      target = build_runner(x: 200, y: 110) # Slightly offset but within radius (20)
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "returns nil when target is outside ray path" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0) # Facing east
      target = build_runner(x: 200, y: 150) # Too far offset (50 > radius of 20)
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "returns closest target when multiple in line" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      near_target = build_runner(x: 200, y: 100)
      far_target = build_runner(x: 400, y: 100)
      arena.runners = [shooter, far_target, near_target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal near_target
    end

    it "ignores dead rubots" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      dead_target = build_runner(x: 200, y: 100)
      dead_target.health = 0
      arena.runners = [shooter, dead_target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "works with angle 90 (north)" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 90) # Facing north
      target = build_runner(x: 100, y: 200) # North of shooter
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "works with angle 180 (west)" do
      arena = build_arena
      shooter = build_runner(x: 200, y: 100, turret_angle: 180) # Facing west
      target = build_runner(x: 100, y: 100) # West of shooter
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "works with angle 270 (south)" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 200, turret_angle: 270) # Facing south
      target = build_runner(x: 100, y: 100) # South of shooter
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "works with diagonal angle 45 (northeast)" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 45)
      target = build_runner(x: 200, y: 200) # Northeast, on the 45° line
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "works with diagonal angle 135 (northwest)" do
      arena = build_arena
      shooter = build_runner(x: 200, y: 100, turret_angle: 135)
      target = build_runner(x: 100, y: 200) # Northwest
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "detects target at edge of radius" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 119) # Offset by 19, just inside radius of 20
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal target
    end

    it "misses target just outside radius" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 121) # Offset by 21, just outside radius of 20
      arena.runners = [shooter, target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "does not detect self" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.runners = [shooter]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "detects small rubot with radius 15" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      small_target = build_runner(x: 200, y: 114, klass: SmallProbeTestBot) # Offset 14, inside radius 15
      arena.runners = [shooter, small_target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal small_target
    end

    it "misses small rubot outside its radius" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      small_target = build_runner(x: 200, y: 117, klass: SmallProbeTestBot) # Offset 17, outside radius 16
      arena.runners = [shooter, small_target]

      result = arena.find_probe_target(shooter)

      _(result).must_be_nil
    end

    it "detects large rubot with radius 24" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      large_target = build_runner(x: 200, y: 123, klass: LargeProbeTestBot) # Offset 23, inside radius 24
      arena.runners = [shooter, large_target]

      result = arena.find_probe_target(shooter)

      _(result).must_equal large_target
    end
  end

  describe "#build_probe_result" do
    it "returns empty hash with no attributes" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.velocity_x = 5.0
      target.shield_level = 10
      target.health = 80
      target.energy = 60

      result = arena.build_probe_result(target:, attributes: [])

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
      target = build_runner(x: 200, y: 150)

      result = arena.build_probe_result(target:, attributes: [:position])

      _(result[:x]).must_equal 200
      _(result[:y]).must_equal 150
      _(result.key?(:size)).must_equal false
    end

    it "adds size when requested" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)

      result = arena.build_probe_result(target:, attributes: [:size])

      _(result[:size]).must_equal :medium
      _(result.key?(:velocity_x)).must_equal false
    end

    it "adds velocity when requested" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.velocity_x = 5.0
      target.velocity_y = -3.0

      result = arena.build_probe_result(target:, attributes: [:velocity])

      _(result[:velocity_x]).must_equal 5.0
      _(result[:velocity_y]).must_equal(-3.0)
      _(result.key?(:x)).must_equal false
      _(result.key?(:size)).must_equal false
    end

    it "adds turret_angle when requested" do
      arena = build_arena
      target = build_runner(x: 200, y: 150, turret_angle: 45)

      result = arena.build_probe_result(target:, attributes: [:turret_angle])

      _(result[:turret_angle]).must_equal 45
      _(result.key?(:x)).must_equal false
    end

    it "adds shield_level when requested" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.shield_level = 25

      result = arena.build_probe_result(target:, attributes: [:shield])

      _(result[:shield_level]).must_equal 25
      _(result.key?(:health)).must_equal false
    end

    it "adds health when requested" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.health = 75

      result = arena.build_probe_result(target:, attributes: [:health])

      _(result[:health]).must_equal 75
      _(result.key?(:energy)).must_equal false
    end

    it "adds energy when requested" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.energy = 45

      result = arena.build_probe_result(target:, attributes: [:energy])

      _(result[:energy]).must_equal 45
    end

    it "adds multiple attributes when requested" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.velocity_x = 5.0
      target.velocity_y = -3.0
      target.health = 75

      result = arena.build_probe_result(target:, attributes: %i[position velocity health])

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
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      arena.runners = [shooter, target]

      arena.process_probe(runner: shooter, attributes: [:position])

      result = shooter.instance.probe_result
      _(result).wont_be_nil
      _(result[:x]).must_equal 200
    end

    it "sets probe result to empty hash when no target found" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.runners = [shooter]

      arena.process_probe(runner: shooter, attributes: [:size])

      result = shooter.instance.probe_result
      _(result).must_equal({})
    end

    it "spends zero energy with no attributes" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 50
      arena.runners = [shooter]

      arena.process_probe(runner: shooter, attributes: [])

      _(shooter.energy).must_equal 50
    end

    it "spends 1 energy for size attribute" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 50
      arena.runners = [shooter]

      arena.process_probe(runner: shooter, attributes: [:size])

      _(shooter.energy).must_equal 49
    end

    it "spends energy based on requested attributes" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 50
      arena.runners = [shooter]

      arena.process_probe(runner: shooter, attributes: %i[size velocity])

      _(shooter.energy).must_equal 46 # 50 - 1 (size) - 3 (velocity)
    end

    it "spends full cost for all attributes" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 50
      arena.runners = [shooter]

      arena.process_probe(runner: shooter, attributes: %i[size position velocity shield health energy])

      _(shooter.energy).must_equal 34 # 50 - 1 - 4 - 3 - 2 - 3 - 3 = 34
    end

    it "returns false and drains energy when insufficient" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 2
      arena.runners = [shooter]

      result = arena.process_probe(runner: shooter, attributes: [:health]) # costs 3 (health only)

      _(result).must_equal false
      _(shooter.energy).must_equal 0
    end

    it "updates probe result when target moves out of sight" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      arena.runners = [shooter, target]

      arena.process_probe(runner: shooter, attributes: [:size])
      first_result = shooter.instance.probe_result
      _(first_result).wont_be_empty

      target.y = 200
      arena.process_probe(runner: shooter, attributes: [:size])
      second_result = shooter.instance.probe_result

      _(second_result).must_be_empty
    end

    it "updates probe result when new target appears" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.runners = [shooter]

      arena.process_probe(runner: shooter, attributes: [:position])
      first_result = shooter.instance.probe_result
      _(first_result).must_be_empty

      target = build_runner(x: 200, y: 100)
      arena.runners = [shooter, target]
      arena.process_probe(runner: shooter, attributes: [:position])
      second_result = shooter.instance.probe_result

      _(second_result).wont_be_empty
      _(second_result[:x]).must_equal 200
    end

    it "returns size only when requested" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      small_target = build_runner(x: 200, y: 100, klass: SmallProbeTestBot)
      arena.runners = [shooter, small_target]

      arena.process_probe(runner: shooter, attributes: [:size])
      result = shooter.instance.probe_result

      _(result[:size]).must_equal :small
    end

    it "does not return size when not requested" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      arena.runners = [shooter, target]

      arena.process_probe(runner: shooter, attributes: [])
      result = shooter.instance.probe_result

      _(result.key?(:size)).must_equal false
    end
  end

  describe "#in_arc?" do
    it "returns true for target directly in front within distance" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 200, x: 200, y: 100)

      _(result).must_equal true
    end

    it "returns false for target beyond max distance" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 50, x: 200, y: 100)

      _(result).must_equal false
    end

    it "returns true for target within arc angle" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      # Target at 10 degrees, arc is 30 degrees (±15)
      target_x = 100 + (100 * Math.cos(10 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(10 * Math::PI / 180))

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal true
    end

    it "returns false for target outside arc angle" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      # Target at 45 degrees, arc is 30 degrees (±15)
      target_x = 100 + (100 * Math.cos(45 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(45 * Math::PI / 180))

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal false
    end

    it "handles turret angle 90 (north)" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 90)

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 200, x: 100, y: 200)

      _(result).must_equal true
    end

    it "handles turret angle 180 (west)" do
      arena = build_arena
      scanner = build_runner(x: 200, y: 100, turret_angle: 180)

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 200, x: 100, y: 100)

      _(result).must_equal true
    end

    it "handles turret angle 270 (south)" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 200, turret_angle: 270)

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 200, x: 100, y: 100)

      _(result).must_equal true
    end

    it "returns true at edge of arc angle" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      # Target at exactly 15 degrees, arc is 30 degrees (±15)
      target_x = 100 + (100 * Math.cos(15 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(15 * Math::PI / 180))

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal true
    end

    it "returns false just outside arc angle" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      # Target at 16 degrees, arc is 30 degrees (±15)
      target_x = 100 + (100 * Math.cos(16 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(16 * Math::PI / 180))

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal false
    end

    it "handles negative arc angles (behind turret direction)" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      # Target at -10 degrees
      target_x = 100 + (100 * Math.cos(-10 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(-10 * Math::PI / 180))

      result = arena.in_arc?(runner: scanner, angle: 30, distance: 200, x: target_x, y: target_y)

      _(result).must_equal true
    end

    it "handles wraparound at 360 degrees" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 350)
      # Target at 10 degrees (20 degree difference across 0)
      target_x = 100 + (100 * Math.cos(10 * Math::PI / 180))
      target_y = 100 + (100 * Math.sin(10 * Math::PI / 180))

      result = arena.in_arc?(runner: scanner, angle: 60, distance: 200, x: target_x, y: target_y)

      _(result).must_equal true
    end
  end

  describe "#process_scan" do
    it "calculates correct energy cost for base scan" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 100
      arena.runners = [scanner]

      arena.process_scan(runner: scanner, angle: 20, distance: 100, velocity: false, owner: false)

      # Cost: 3 base + ceil(20/20) + ceil(100/100) = 3 + 1 + 1 = 5
      _(scanner.energy).must_equal 95
    end

    it "calculates correct energy cost with velocity" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 100
      arena.runners = [scanner]

      arena.process_scan(runner: scanner, angle: 20, distance: 100, velocity: true, owner: false)

      # Cost: 3 base + 1 + 1 + 2 velocity = 7
      _(scanner.energy).must_equal 93
    end

    it "calculates correct cost for large scan area" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 100
      arena.runners = [scanner]

      arena.process_scan(runner: scanner, angle: 90, distance: 300, velocity: false, owner: false)

      # Cost: 3 base + ceil(90/20) + ceil(300/100) = 3 + 5 + 3 = 11
      _(scanner.energy).must_equal 89
    end

    it "returns empty array when no targets in arc" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 100, y: 300) # North, not in east-facing arc
      arena.runners = [scanner, target]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_result

      _(result).must_equal []
    end

    it "returns rubot in arc" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      arena.runners = [scanner, target]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_result

      _(result.length).must_equal 1
      _(result[0][:x]).must_equal 200
      _(result[0][:y]).must_equal 100
      _(result[0][:type]).must_equal :rubot
    end

    it "returns multiple rubots in arc" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      target1 = build_runner(x: 200, y: 100)
      target2 = build_runner(x: 250, y: 110)
      arena.runners = [scanner, target1, target2]

      arena.process_scan(runner: scanner, angle: 30, distance: 300, velocity: false, owner: false)
      result = scanner.instance.scan_result

      _(result.length).must_equal 2
      _(result.all? { |r| r[:type] == :rubot }).must_equal true
    end

    it "does not include self in results" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.runners = [scanner]

      arena.process_scan(runner: scanner, angle: 360, distance: 500, velocity: false, owner: false)
      result = scanner.instance.scan_result

      _(result).must_equal []
    end

    it "does not include dead rubots" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      dead_target = build_runner(x: 200, y: 100)
      dead_target.health = 0
      arena.runners = [scanner, dead_target]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_result

      _(result).must_equal []
    end

    it "includes velocity when requested" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      target.velocity_x = 5.0
      target.velocity_y = -3.0
      arena.runners = [scanner, target]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: true, owner: false)
      result = scanner.instance.scan_result

      _(result[0][:velocity_x]).must_equal 5.0
      _(result[0][:velocity_y]).must_equal(-3.0)
    end

    it "does not include velocity when not requested" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      target.velocity_x = 5.0
      arena.runners = [scanner, target]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_result

      _(result[0].key?(:velocity_x)).must_equal false
    end

    it "detects bullets in arc" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      bullet = Rubowar::Bullet.new(x: 200, y: 100, angle: 180, damage: 10, owner: scanner)
      arena.runners = [scanner]
      arena.bullets = [bullet]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_result

      _(result.length).must_equal 1
      _(result[0][:type]).must_equal :bullet
    end

    it "includes bullet velocity when requested" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      bullet = Rubowar::Bullet.new(x: 200, y: 100, angle: 180, damage: 10, owner: scanner)
      arena.runners = [scanner]
      arena.bullets = [bullet]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: true, owner: false)
      result = scanner.instance.scan_result

      _(result[0].key?(:velocity_x)).must_equal true
      _(result[0].key?(:velocity_y)).must_equal true
    end

    it "returns both rubots and bullets in arc" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      bullet = Rubowar::Bullet.new(x: 250, y: 100, angle: 180, damage: 10, owner: scanner)
      arena.runners = [scanner, target]
      arena.bullets = [bullet]

      arena.process_scan(runner: scanner, angle: 30, distance: 300, velocity: false, owner: false)
      result = scanner.instance.scan_result

      _(result.length).must_equal 2
      types = result.map { |r| r[:type] }
      _(types).must_include :rubot
      _(types).must_include :bullet
    end

    it "returns false and drains energy when insufficient" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 3
      arena.runners = [scanner]

      result = arena.process_scan(runner: scanner, angle: 20, distance: 100, velocity: false, owner: false)

      _(result).must_equal false
      _(scanner.energy).must_equal 0
    end

    it "adds owner cost when owner option is true" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      scanner.energy = 100
      arena.runners = [scanner]

      arena.process_scan(runner: scanner, angle: 20, distance: 100, velocity: false, owner: true)

      # Cost: 3 base + 1 angle + 1 distance + 1 owner = 6
      _(scanner.energy).must_equal 94
    end

    it "includes owner info for bullets when requested" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      shooter = build_runner(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 200, y: 100, angle: 180, damage: 10, owner: shooter)
      arena.runners = [scanner, shooter]
      arena.bullets = [bullet]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: false, owner: true)
      result = scanner.instance.scan_result

      bullet_result = result.find { |r| r[:type] == :bullet }
      _(bullet_result[:owner]).must_equal "ProbeTestBot"
    end

    it "sets owner to nil for rubots when owner requested" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      arena.runners = [scanner, target]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: false, owner: true)
      result = scanner.instance.scan_result

      _(result[0][:owner]).must_be_nil
    end

    it "does not include owner when not requested" do
      arena = build_arena
      scanner = build_runner(x: 100, y: 100, turret_angle: 0)
      shooter = build_runner(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 200, y: 100, angle: 180, damage: 10, owner: shooter)
      arena.runners = [scanner, shooter]
      arena.bullets = [bullet]

      arena.process_scan(runner: scanner, angle: 30, distance: 200, velocity: false, owner: false)
      result = scanner.instance.scan_result

      bullet_result = result.find { |r| r[:type] == :bullet }
      _(bullet_result.key?(:owner)).must_equal false
    end
  end

  describe "#within_distance?" do
    it "returns true for target within distance" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)

      result = arena.within_distance?(runner:, distance: 150, x: 200, y: 100)

      _(result).must_equal true
    end

    it "returns false for target beyond distance" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)

      result = arena.within_distance?(runner:, distance: 50, x: 200, y: 100)

      _(result).must_equal false
    end

    it "returns true at exact distance" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)

      result = arena.within_distance?(runner:, distance: 100, x: 200, y: 100)

      _(result).must_equal true
    end

    it "works in all directions" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)

      # North
      _(arena.within_distance?(runner:, distance: 100, x: 100, y: 200)).must_equal true
      # South
      _(arena.within_distance?(runner:, distance: 100, x: 100, y: 0)).must_equal true
      # East
      _(arena.within_distance?(runner:, distance: 100, x: 200, y: 100)).must_equal true
      # West
      _(arena.within_distance?(runner:, distance: 100, x: 0, y: 100)).must_equal true
    end
  end

  describe "#process_pulse" do
    it "calculates correct energy cost" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.energy = 100
      arena.runners = [runner]

      arena.process_pulse(runner:, distance: 75, owner: false)

      # Cost: 2 base + ceil(75/75) = 2 + 1 = 3
      _(runner.energy).must_equal 97
    end

    it "calculates correct cost for longer distance" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.energy = 100
      arena.runners = [runner]

      arena.process_pulse(runner:, distance: 200, owner: false)

      # Cost: 2 base + ceil(200/75) = 2 + 3 = 5
      _(runner.energy).must_equal 95
    end

    it "returns empty array when no targets in range" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      target = build_runner(x: 500, y: 500) # Far away
      arena.runners = [runner, target]

      arena.process_pulse(runner:, distance: 100, owner: false)
      result = runner.instance.pulse_result

      _(result).must_equal []
    end

    it "returns rubot in range" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      target = build_runner(x: 150, y: 100) # 50 units away
      arena.runners = [runner, target]

      arena.process_pulse(runner:, distance: 100, owner: false)
      result = runner.instance.pulse_result

      _(result.length).must_equal 1
      _(result[0][:x]).must_equal 150
      _(result[0][:y]).must_equal 100
      _(result[0][:type]).must_equal :rubot
    end

    it "returns multiple rubots in range" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      target1 = build_runner(x: 150, y: 100)
      target2 = build_runner(x: 100, y: 150)
      arena.runners = [runner, target1, target2]

      arena.process_pulse(runner:, distance: 100, owner: false)
      result = runner.instance.pulse_result

      _(result.length).must_equal 2
      _(result.all? { |r| r[:type] == :rubot }).must_equal true
    end

    it "does not include self in results" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      arena.runners = [runner]

      arena.process_pulse(runner:, distance: 500, owner: false)
      result = runner.instance.pulse_result

      _(result).must_equal []
    end

    it "does not include dead rubots" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      dead_target = build_runner(x: 150, y: 100)
      dead_target.health = 0
      arena.runners = [runner, dead_target]

      arena.process_pulse(runner:, distance: 100, owner: false)
      result = runner.instance.pulse_result

      _(result).must_equal []
    end

    it "detects bullets in range" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      bullet = Rubowar::Bullet.new(x: 150, y: 100, angle: 180, damage: 10, owner: runner)
      arena.runners = [runner]
      arena.bullets = [bullet]

      arena.process_pulse(runner:, distance: 100, owner: false)
      result = runner.instance.pulse_result

      _(result.length).must_equal 1
      _(result[0][:type]).must_equal :bullet
    end

    it "returns both rubots and bullets in range" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      target = build_runner(x: 150, y: 100)
      bullet = Rubowar::Bullet.new(x: 100, y: 150, angle: 180, damage: 10, owner: runner)
      arena.runners = [runner, target]
      arena.bullets = [bullet]

      arena.process_pulse(runner:, distance: 100, owner: false)
      result = runner.instance.pulse_result

      _(result.length).must_equal 2
      types = result.map { |r| r[:type] }
      _(types).must_include :rubot
      _(types).must_include :bullet
    end

    it "does not include velocity data" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      target = build_runner(x: 150, y: 100)
      target.velocity_x = 5.0
      target.velocity_y = -3.0
      arena.runners = [runner, target]

      arena.process_pulse(runner:, distance: 100, owner: false)
      result = runner.instance.pulse_result

      _(result[0].key?(:velocity_x)).must_equal false
      _(result[0].key?(:velocity_y)).must_equal false
    end

    it "returns false and drains energy when insufficient" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.energy = 2
      arena.runners = [runner]

      result = arena.process_pulse(runner:, distance: 75, owner: false)

      _(result).must_equal false
      _(runner.energy).must_equal 0
    end

    it "detects targets in all directions" do
      arena = build_arena
      runner = build_runner(x: 200, y: 200)
      north = build_runner(x: 200, y: 250)
      south = build_runner(x: 200, y: 150)
      east = build_runner(x: 250, y: 200)
      west = build_runner(x: 150, y: 200)
      arena.runners = [runner, north, south, east, west]

      arena.process_pulse(runner:, distance: 100, owner: false)
      result = runner.instance.pulse_result

      _(result.length).must_equal 4
    end

    it "adds owner cost when owner option is true" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.energy = 100
      arena.runners = [runner]

      arena.process_pulse(runner:, distance: 75, owner: true)

      # Cost: 2 base + 1 distance + 1 owner = 4
      _(runner.energy).must_equal 96
    end

    it "includes owner info for bullets when requested" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      shooter = build_runner(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 150, y: 100, angle: 180, damage: 10, owner: shooter)
      arena.runners = [runner, shooter]
      arena.bullets = [bullet]

      arena.process_pulse(runner:, distance: 100, owner: true)
      result = runner.instance.pulse_result

      bullet_result = result.find { |r| r[:type] == :bullet }
      _(bullet_result[:owner]).must_equal "ProbeTestBot"
    end

    it "sets owner to nil for rubots when owner requested" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      target = build_runner(x: 150, y: 100)
      arena.runners = [runner, target]

      arena.process_pulse(runner:, distance: 100, owner: true)
      result = runner.instance.pulse_result

      _(result[0][:owner]).must_be_nil
    end

    it "does not include owner when not requested" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      shooter = build_runner(x: 300, y: 300)
      bullet = Rubowar::Bullet.new(x: 150, y: 100, angle: 180, damage: 10, owner: shooter)
      arena.runners = [runner, shooter]
      arena.bullets = [bullet]

      arena.process_pulse(runner:, distance: 100, owner: false)
      result = runner.instance.pulse_result

      bullet_result = result.find { |r| r[:type] == :bullet }
      _(bullet_result.key?(:owner)).must_equal false
    end
  end

  describe "#spawn_energon" do
    it "creates an energon in the arena" do
      arena = build_arena
      arena.runners = []

      energon = arena.spawn_energon(100)

      _(energon).must_be_instance_of Rubowar::Energon
      _(arena.energons.length).must_equal 1
    end

    it "spawns at center when no rubots exist" do
      arena = build_arena
      arena.runners = []

      energon = arena.spawn_energon(100)

      _(energon.x).must_equal arena.width / 2.0
      _(energon.y).must_equal arena.height / 2.0
    end

    it "spawns away from rubots" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      arena.runners = [runner]

      energon = arena.spawn_energon(100)

      distance = Math.sqrt(((energon.x - runner.x)**2) + ((energon.y - runner.y)**2))
      _(distance).must_be :>, 50 # Should spawn away from rubot
    end

    it "records spawn chronon" do
      arena = build_arena
      arena.runners = []

      energon = arena.spawn_energon(150)

      _(energon.spawn_chronon).must_equal 150
    end

    it "maximizes minimum distance from all rubots" do
      arena = build_arena
      runner1 = build_runner(x: 200, y: 200)
      runner2 = build_runner(x: 600, y: 400)
      arena.runners = [runner1, runner2]

      energon = arena.spawn_energon(100)

      # Energon should be positioned to maximize distance from nearest rubot
      dist1 = Math.sqrt(((energon.x - runner1.x)**2) + ((energon.y - runner1.y)**2))
      dist2 = Math.sqrt(((energon.x - runner2.x)**2) + ((energon.y - runner2.y)**2))
      min_dist = [dist1, dist2].min

      # Should be reasonably far from both (not right next to either)
      _(min_dist).must_be :>, 100
    end

    it "respects wall buffer" do
      arena = build_arena
      arena.runners = []
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
      runner = build_runner(x: 100, y: 100)
      arena.runners = [runner]

      collections = arena.check_energon_collection(100)

      _(collections).must_equal []
    end

    it "returns empty array when rubot not touching energon" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      arena.runners = [runner]
      energon = Rubowar::Energon.new(x: 500, y: 500, spawn_chronon: 50)
      arena.energons = [energon]

      collections = arena.check_energon_collection(100)

      _(collections).must_equal []
    end

    it "collects energon when rubot overlaps" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      arena.runners = [runner]
      # Place energon within collection range (rubot radius + energon radius)
      energon = Rubowar::Energon.new(x: 100 + runner.radius, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      collections = arena.check_energon_collection(100)

      _(collections.length).must_equal 1
      _(collections[0][:runner]).must_equal runner
      _(collections[0][:energon]).must_equal energon
    end

    it "removes collected energon from arena" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      arena.runners = [runner]
      energon = Rubowar::Energon.new(x: 100, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      arena.check_energon_collection(100)

      _(arena.energons).must_be_empty
    end

    it "adds energy to collecting rubot" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.energy = 50
      arena.runners = [runner]
      energon = Rubowar::Energon.new(x: 100, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      arena.check_energon_collection(100)

      _(runner.energy).must_be :>, 50
    end

    it "caps energy at max" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.energy = runner.max_energy - 1
      arena.runners = [runner]
      energon = Rubowar::Energon.new(x: 100, y: 100, spawn_chronon: 0)
      arena.energons = [energon]

      arena.check_energon_collection(100) # 100 chronons old = 101 value

      _(runner.energy).must_equal runner.max_energy
    end

    it "ignores dead rubots" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.health = 0
      arena.runners = [runner]
      energon = Rubowar::Energon.new(x: 100, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      collections = arena.check_energon_collection(100)

      _(collections).must_be_empty
      _(arena.energons.length).must_equal 1
    end

    it "returns collection amount based on energon value" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100)
      runner.energy = 0
      arena.runners = [runner]
      energon = Rubowar::Energon.new(x: 100, y: 100, spawn_chronon: 50)
      arena.energons = [energon]

      collections = arena.check_energon_collection(100) # 50 chronons old

      expected_value = energon.value_int(100)
      _(collections[0][:amount]).must_equal expected_value
    end
  end
end
