# frozen_string_literal: true

require "test_helper"

def build_test_actor(x: 100, y: 100, vx: 0, vy: 0)
  klass = Class.new do
    include Rubowar::Rubot

    size :medium
    def act; end
  end
  actor = Rubowar::LocalActor.new(klass)
  actor.x = x
  actor.y = y
  actor.velocity_x = vx
  actor.velocity_y = vy
  actor
end

describe Rubowar::CollisionResponse do
  describe "#apply_positions!" do
    it "adjusts positions of both actors" do
      actor_a = build_test_actor(x: 100, y: 100)
      actor_b = build_test_actor(x: 110, y: 110)
      response = Rubowar::CollisionResponse.new(
        actor_a:, actor_b:,
        pos_adjust_a_x: -5, pos_adjust_a_y: -5,
        pos_adjust_b_x: 5, pos_adjust_b_y: 5,
        vel_adjust_a_x: 0, vel_adjust_a_y: 0,
        vel_adjust_b_x: 0, vel_adjust_b_y: 0,
        damage_to_a: 0, damage_to_b: 0
      )

      response.apply_positions!

      _(actor_a.x).must_equal 95
      _(actor_a.y).must_equal 95
      _(actor_b.x).must_equal 115
      _(actor_b.y).must_equal 115
    end

    it "handles zero adjustments" do
      actor_a = build_test_actor(x: 100, y: 100)
      actor_b = build_test_actor(x: 110, y: 110)
      response = Rubowar::CollisionResponse.new(
        actor_a:, actor_b:,
        pos_adjust_a_x: 0, pos_adjust_a_y: 0,
        pos_adjust_b_x: 0, pos_adjust_b_y: 0,
        vel_adjust_a_x: 0, vel_adjust_a_y: 0,
        vel_adjust_b_x: 0, vel_adjust_b_y: 0,
        damage_to_a: 0, damage_to_b: 0
      )

      response.apply_positions!

      _(actor_a.x).must_equal 100
      _(actor_a.y).must_equal 100
      _(actor_b.x).must_equal 110
      _(actor_b.y).must_equal 110
    end
  end

  describe "#apply_velocities!" do
    it "adjusts velocities of both actors" do
      actor_a = build_test_actor(vx: 5, vy: 5)
      actor_b = build_test_actor(vx: -5, vy: -5)
      response = Rubowar::CollisionResponse.new(
        actor_a:, actor_b:,
        pos_adjust_a_x: 0, pos_adjust_a_y: 0,
        pos_adjust_b_x: 0, pos_adjust_b_y: 0,
        vel_adjust_a_x: -2, vel_adjust_a_y: -2,
        vel_adjust_b_x: 2, vel_adjust_b_y: 2,
        damage_to_a: 0, damage_to_b: 0
      )

      response.apply_velocities!

      _(actor_a.velocity_x).must_equal 3
      _(actor_a.velocity_y).must_equal 3
      _(actor_b.velocity_x).must_equal(-3)
      _(actor_b.velocity_y).must_equal(-3)
    end

    it "handles zero adjustments" do
      actor_a = build_test_actor(vx: 5, vy: 5)
      actor_b = build_test_actor(vx: -5, vy: -5)
      response = Rubowar::CollisionResponse.new(
        actor_a:, actor_b:,
        pos_adjust_a_x: 0, pos_adjust_a_y: 0,
        pos_adjust_b_x: 0, pos_adjust_b_y: 0,
        vel_adjust_a_x: 0, vel_adjust_a_y: 0,
        vel_adjust_b_x: 0, vel_adjust_b_y: 0,
        damage_to_a: 0, damage_to_b: 0
      )

      response.apply_velocities!

      _(actor_a.velocity_x).must_equal 5
      _(actor_a.velocity_y).must_equal 5
      _(actor_b.velocity_x).must_equal(-5)
      _(actor_b.velocity_y).must_equal(-5)
    end
  end

  describe "#apply_damage_and_callbacks!" do
    it "applies collision damage to both actors" do
      actor_a = build_test_actor
      actor_b = build_test_actor
      actor_a.health = 100
      actor_b.health = 100
      response = Rubowar::CollisionResponse.new(
        actor_a:, actor_b:,
        pos_adjust_a_x: 0, pos_adjust_a_y: 0,
        pos_adjust_b_x: 0, pos_adjust_b_y: 0,
        vel_adjust_a_x: 0, vel_adjust_a_y: 0,
        vel_adjust_b_x: 0, vel_adjust_b_y: 0,
        damage_to_a: 10, damage_to_b: 15
      )

      response.apply_damage_and_callbacks!

      _(actor_a.health).must_equal 90
      _(actor_b.health).must_equal 85
    end

    it "handles zero damage" do
      actor_a = build_test_actor
      actor_b = build_test_actor
      actor_a.health = 100
      actor_b.health = 100
      response = Rubowar::CollisionResponse.new(
        actor_a:, actor_b:,
        pos_adjust_a_x: 0, pos_adjust_a_y: 0,
        pos_adjust_b_x: 0, pos_adjust_b_y: 0,
        vel_adjust_a_x: 0, vel_adjust_a_y: 0,
        vel_adjust_b_x: 0, vel_adjust_b_y: 0,
        damage_to_a: 0, damage_to_b: 0
      )

      response.apply_damage_and_callbacks!

      _(actor_a.health).must_equal 100
      _(actor_b.health).must_equal 100
    end
  end

  describe "integration" do
    it "applies all effects in sequence" do
      actor_a = build_test_actor(x: 100, y: 100, vx: 5, vy: 5)
      actor_b = build_test_actor(x: 110, y: 110, vx: -5, vy: -5)
      actor_a.health = 100
      actor_b.health = 100
      response = Rubowar::CollisionResponse.new(
        actor_a:, actor_b:,
        pos_adjust_a_x: -5, pos_adjust_a_y: -5,
        pos_adjust_b_x: 5, pos_adjust_b_y: 5,
        vel_adjust_a_x: -2, vel_adjust_a_y: -2,
        vel_adjust_b_x: 2, vel_adjust_b_y: 2,
        damage_to_a: 10, damage_to_b: 15
      )

      response.apply_positions!
      response.apply_velocities!
      response.apply_damage_and_callbacks!

      # Verify positions
      _(actor_a.x).must_equal 95
      _(actor_a.y).must_equal 95
      _(actor_b.x).must_equal 115
      _(actor_b.y).must_equal 115

      # Verify velocities
      _(actor_a.velocity_x).must_equal 3
      _(actor_a.velocity_y).must_equal 3
      _(actor_b.velocity_x).must_equal(-3)
      _(actor_b.velocity_y).must_equal(-3)

      # Verify damage
      _(actor_a.health).must_equal 90
      _(actor_b.health).must_equal 85
    end
  end
end
