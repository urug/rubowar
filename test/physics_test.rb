# frozen_string_literal: true

require "test_helper"

describe Rubowar::Physics do
  describe ".mass_factor" do
    it "returns 1.0 for medium radius" do
      mass = Rubowar::Physics.mass_factor(20)

      _(mass).must_equal 1.0
    end

    it "returns area ratio for small radius" do
      mass = Rubowar::Physics.mass_factor(16)

      _(mass).must_be_close_to 0.64, 0.001 # (16/20)^2
    end

    it "returns area ratio for large radius" do
      mass = Rubowar::Physics.mass_factor(24)

      _(mass).must_be_close_to 1.44, 0.001 # (24/20)^2
    end
  end

  describe ".distance" do
    it "returns 0 for same point" do
      dist = Rubowar::Physics.distance(x1: 100, y1: 100, x2: 100, y2: 100)

      _(dist).must_equal 0
    end

    it "returns horizontal distance" do
      dist = Rubowar::Physics.distance(x1: 0, y1: 0, x2: 30, y2: 0)

      _(dist).must_equal 30
    end

    it "returns vertical distance" do
      dist = Rubowar::Physics.distance(x1: 0, y1: 0, x2: 0, y2: 40)

      _(dist).must_equal 40
    end

    it "returns diagonal distance" do
      dist = Rubowar::Physics.distance(x1: 0, y1: 0, x2: 30, y2: 40)

      _(dist).must_equal 50 # 3-4-5 triangle scaled by 10
    end
  end

  describe ".collision_damage" do
    it "returns base damage when no relative velocity" do
      damage = Rubowar::Physics.collision_damage(rel_vx: 0, rel_vy: 0, mass: 1.0)

      _(damage).must_equal 2
    end

    it "increases damage with closing speed" do
      damage = Rubowar::Physics.collision_damage(rel_vx: 20, rel_vy: 0, mass: 1.0)

      _(damage).must_equal 12 # 2 + 1.0 * 20 * 0.5
    end

    it "scales damage with mass" do
      small_damage = Rubowar::Physics.collision_damage(rel_vx: 20, rel_vy: 0, mass: 0.64)
      large_damage = Rubowar::Physics.collision_damage(rel_vx: 20, rel_vy: 0, mass: 1.44)

      _(small_damage).must_equal 8  # 2 + 0.64 * 20 * 0.5
      _(large_damage).must_equal 16 # 2 + 1.44 * 20 * 0.5
    end

    it "uses combined velocity components" do
      damage = Rubowar::Physics.collision_damage(rel_vx: 30, rel_vy: 40, mass: 1.0)

      _(damage).must_equal 27 # 2 + 1.0 * 50 * 0.5 (3-4-5 triangle)
    end
  end

  describe ".wall_damage" do
    it "returns 0 when moving parallel to wall" do
      damage = Rubowar::Physics.wall_damage(
        vx: 10, vy: 0,
        normal_x: 0.0, normal_y: 1.0,
        mass: 1.0
      )

      _(damage).must_equal 0
    end

    it "returns 0 when moving away from wall" do
      damage = Rubowar::Physics.wall_damage(
        vx: 10, vy: 0,
        normal_x: 1.0, normal_y: 0.0,
        mass: 1.0
      )

      _(damage).must_equal 0
    end

    it "returns damage when moving into wall" do
      damage = Rubowar::Physics.wall_damage(
        vx: -20, vy: 0,
        normal_x: 1.0, normal_y: 0.0,
        mass: 1.0
      )

      _(damage).must_equal 12 # 2 + 1.0 * 20 * 0.5
    end

    it "scales damage with mass" do
      damage = Rubowar::Physics.wall_damage(
        vx: -20, vy: 0,
        normal_x: 1.0, normal_y: 0.0,
        mass: 1.44
      )

      _(damage).must_equal 16 # 2 + 1.44 * 20 * 0.5
    end
  end

  describe ".wall_bounce" do
    it "returns nil when moving away from wall" do
      result = Rubowar::Physics.wall_bounce(
        vx: 10, vy: 0,
        normal_x: 1.0, normal_y: 0.0,
        bot_mass: 1.0
      )

      _(result).must_be_nil
    end

    it "returns nil when moving parallel to wall" do
      result = Rubowar::Physics.wall_bounce(
        vx: 10, vy: 0,
        normal_x: 0.0, normal_y: 1.0,
        bot_mass: 1.0
      )

      _(result).must_be_nil
    end

    it "reverses velocity component when hitting wall" do
      result = Rubowar::Physics.wall_bounce(
        vx: -20, vy: 0,
        normal_x: 1.0, normal_y: 0.0,
        bot_mass: 1.0
      )

      _(result[:vx]).must_be :>, 0 # Bounced back
      _(result[:vy]).must_be_close_to 0, 0.001
    end

    it "preserves perpendicular velocity component" do
      result = Rubowar::Physics.wall_bounce(
        vx: -20, vy: 10,
        normal_x: 1.0, normal_y: 0.0,
        bot_mass: 1.0
      )

      _(result[:vy]).must_be_close_to 10, 0.001
    end

    it "reduces speed due to elasticity less than 1" do
      result = Rubowar::Physics.wall_bounce(
        vx: -20, vy: 0,
        normal_x: 1.0, normal_y: 0.0,
        bot_mass: 1.0
      )

      _(result[:vx]).must_be :<, 20 # Less than original speed
    end
  end

  describe ".collision_bounce" do
    it "returns zero adjustments when bots already separating" do
      result = Rubowar::Physics.collision_bounce(
        a_vx: -10, a_vy: 0,
        b_vx: 10, b_vy: 0,
        nx: 1.0, ny: 0.0,
        mass_a: 1.0, mass_b: 1.0
      )

      _(result[:a_vx]).must_equal 0.0
      _(result[:a_vy]).must_equal 0.0
      _(result[:b_vx]).must_equal 0.0
      _(result[:b_vy]).must_equal 0.0
    end

    it "applies equal opposite adjustments for equal masses" do
      result = Rubowar::Physics.collision_bounce(
        a_vx: 10, a_vy: 0,
        b_vx: -10, b_vy: 0,
        nx: 1.0, ny: 0.0,
        mass_a: 1.0, mass_b: 1.0
      )

      _(result[:a_vx]).must_be_close_to(-result[:b_vx], 0.001)
    end

    it "applies larger adjustment to lighter bot" do
      result = Rubowar::Physics.collision_bounce(
        a_vx: 10, a_vy: 0,
        b_vx: -10, b_vy: 0,
        nx: 1.0, ny: 0.0,
        mass_a: 0.5, mass_b: 2.0
      )

      _(result[:a_vx].abs).must_be :>, result[:b_vx].abs
    end

    it "conserves momentum direction along collision normal" do
      result = Rubowar::Physics.collision_bounce(
        a_vx: 10, a_vy: 0,
        b_vx: 0, b_vy: 0,
        nx: 1.0, ny: 0.0,
        mass_a: 1.0, mass_b: 1.0
      )

      # A should slow down, B should speed up
      _(result[:a_vx]).must_be :<, 0
      _(result[:b_vx]).must_be :>, 0
    end
  end

  describe ".collision_separation" do
    it "pushes bots apart equally" do
      result = Rubowar::Physics.collision_separation(
        a_x: 100, a_y: 100,
        b_x: 110, b_y: 100,
        distance: 10,
        overlap: 4
      )

      _(result[:a_x]).must_be_close_to(-2, 0.001) # Pushed left
      _(result[:b_x]).must_be_close_to(2, 0.001)  # Pushed right
      _(result[:a_y]).must_be_close_to(0, 0.001)
      _(result[:b_y]).must_be_close_to(0, 0.001)
    end

    it "separates along the line between centers" do
      result = Rubowar::Physics.collision_separation(
        a_x: 100, a_y: 100,
        b_x: 140, b_y: 100,
        distance: 40,
        overlap: 8
      )

      # Direction from A to B is (40, 0), unit vector (1, 0)
      # A pushed left by overlap/2 = 4, B pushed right by 4
      _(result[:a_x]).must_be_close_to(-4, 0.001)
      _(result[:a_y]).must_be_close_to(0, 0.001)
      _(result[:b_x]).must_be_close_to(4, 0.001)
      _(result[:b_y]).must_be_close_to(0, 0.001)
    end

    it "splits overlap evenly between both bots" do
      result = Rubowar::Physics.collision_separation(
        a_x: 100, a_y: 100,
        b_x: 120, b_y: 100,
        distance: 20,
        overlap: 8
      )

      total_separation = (result[:a_x] - result[:b_x]).abs
      _(total_separation).must_be_close_to 8, 0.001
    end

    it "handles zero distance using velocity to determine separation" do
      result = Rubowar::Physics.collision_separation(
        a_x: 100, a_y: 100,
        b_x: 100, b_y: 100,
        distance: 0,
        overlap: 40,
        a_vx: 5, a_vy: 0,
        b_vx: -5, b_vy: 0
      )

      # Should separate along relative velocity direction (x-axis)
      _(result[:a_x]).must_be :>, 0
      _(result[:b_x]).must_be :<, 0
      _(result[:a_y]).must_be_close_to 0, 0.001
      _(result[:b_y]).must_be_close_to 0, 0.001
    end

    it "handles zero distance with both stationary using arbitrary direction" do
      result = Rubowar::Physics.collision_separation(
        a_x: 100, a_y: 100,
        b_x: 100, b_y: 100,
        distance: 0,
        overlap: 40,
        a_vx: 0, a_vy: 0,
        b_vx: 0, b_vy: 0
      )

      # Should separate along arbitrary axis (x-axis by default)
      total_separation = (result[:a_x] - result[:b_x]).abs + (result[:a_y] - result[:b_y]).abs
      _(total_separation).must_be_close_to 40, 0.001
    end
  end

  describe ".thrust_direction_multiplier" do
    it "returns 1.0 when stationary" do
      mult = Rubowar::Physics.thrust_direction_multiplier(
        vx: 0, vy: 0,
        thrust_angle: 90,
        speed: 0
      )

      _(mult).must_equal 1.0
    end

    it "returns 1.0 when thrusting in same direction" do
      mult = Rubowar::Physics.thrust_direction_multiplier(
        vx: 10, vy: 0,
        thrust_angle: 0,
        speed: 10
      )

      _(mult).must_be_close_to 1.0, 0.001
    end

    it "returns 1.5 when thrusting perpendicular" do
      mult = Rubowar::Physics.thrust_direction_multiplier(
        vx: 10, vy: 0,
        thrust_angle: 90,
        speed: 10
      )

      _(mult).must_be_close_to 1.5, 0.001
    end

    it "returns 2.0 when thrusting opposite direction" do
      mult = Rubowar::Physics.thrust_direction_multiplier(
        vx: 10, vy: 0,
        thrust_angle: 180,
        speed: 10
      )

      _(mult).must_be_close_to 2.0, 0.001
    end

    it "handles negative angles correctly" do
      mult = Rubowar::Physics.thrust_direction_multiplier(
        vx: 10, vy: 0,
        thrust_angle: -90,
        speed: 10
      )

      _(mult).must_be_close_to 1.5, 0.001
    end
  end

  describe ".thrust_cost" do
    it "scales quadratically with speed" do
      cost_10 = Rubowar::Physics.thrust_cost(speed: 10, mass: 1.0, direction_multiplier: 1.0)
      cost_20 = Rubowar::Physics.thrust_cost(speed: 20, mass: 1.0, direction_multiplier: 1.0)

      _(cost_20).must_be :>, cost_10 * 3 # Quadratic scaling
    end

    it "increases with mass" do
      cost_light = Rubowar::Physics.thrust_cost(speed: 15, mass: 0.5, direction_multiplier: 1.0)
      cost_heavy = Rubowar::Physics.thrust_cost(speed: 15, mass: 2.0, direction_multiplier: 1.0)

      _(cost_heavy).must_be :>, cost_light
    end

    it "increases with direction_multiplier" do
      cost_same = Rubowar::Physics.thrust_cost(speed: 15, mass: 1.0, direction_multiplier: 1.0)
      cost_opposite = Rubowar::Physics.thrust_cost(speed: 15, mass: 1.0, direction_multiplier: 2.0)

      _(cost_opposite).must_be :>, cost_same
    end
  end

  describe ".thrust_speed_from_energy" do
    it "returns speed proportional to sqrt of energy" do
      speed = Rubowar::Physics.thrust_speed_from_energy(energy: 100, mass: 1.0, direction_multiplier: 1.0)

      _(speed).must_be :>, 0
    end

    it "returns lower speed for higher mass" do
      speed_light = Rubowar::Physics.thrust_speed_from_energy(energy: 100, mass: 0.5, direction_multiplier: 1.0)
      speed_heavy = Rubowar::Physics.thrust_speed_from_energy(energy: 100, mass: 2.0, direction_multiplier: 1.0)

      _(speed_light).must_be :>, speed_heavy
    end

    it "is inverse of thrust_cost" do
      original_speed = 15.0
      mass = 1.0
      direction_multiplier = 1.5

      cost = Rubowar::Physics.thrust_cost(speed: original_speed, mass: mass, direction_multiplier: direction_multiplier)
      recovered_speed = Rubowar::Physics.thrust_speed_from_energy(
        energy: cost, mass: mass, direction_multiplier: direction_multiplier
      )

      _(recovered_speed).must_be_close_to original_speed, 0.1
    end
  end

  describe ".thrust_velocity" do
    it "returns velocity in direction of angle 0 (east)" do
      result = Rubowar::Physics.thrust_velocity(speed: 10, angle: 0, mass: 1.0)

      _(result[:vx]).must_be_close_to 10, 0.001
      _(result[:vy]).must_be_close_to 0, 0.001
    end

    it "returns velocity in direction of angle 90 (north)" do
      result = Rubowar::Physics.thrust_velocity(speed: 10, angle: 90, mass: 1.0)

      _(result[:vx]).must_be_close_to 0, 0.001
      _(result[:vy]).must_be_close_to 10, 0.001
    end

    it "reduces acceleration for heavier mass" do
      light = Rubowar::Physics.thrust_velocity(speed: 10, angle: 0, mass: 0.5)
      heavy = Rubowar::Physics.thrust_velocity(speed: 10, angle: 0, mass: 2.0)

      _(light[:vx]).must_be :>, heavy[:vx]
    end

    it "scales velocity with speed" do
      slow = Rubowar::Physics.thrust_velocity(speed: 5, angle: 0, mass: 1.0)
      fast = Rubowar::Physics.thrust_velocity(speed: 15, angle: 0, mass: 1.0)

      _(fast[:vx]).must_equal slow[:vx] * 3
    end
  end
end
