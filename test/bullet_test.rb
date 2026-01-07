# frozen_string_literal: true

require "test_helper"

describe Rubowar::Bullet do
  describe "initialization" do
    it "sets position from arguments" do
      bullet = Rubowar::Bullet.new(x: 100, y: 200, angle: 0, damage: 15, owner: nil)

      _(bullet.x).must_equal 100.0
      _(bullet.y).must_equal 200.0
    end

    it "sets damage from arguments" do
      bullet = Rubowar::Bullet.new(x: 0, y: 0, angle: 0, damage: 15, owner: nil)

      _(bullet.damage).must_equal 15.0
    end

    it "sets radius to constant value" do
      bullet = Rubowar::Bullet.new(x: 0, y: 0, angle: 0, damage: 10, owner: nil)

      _(bullet.radius).must_equal Rubowar::Config::Combat::BULLET_RADIUS
    end

    it "calculates velocity from angle 0 (east)" do
      bullet = Rubowar::Bullet.new(x: 0, y: 0, angle: 0, damage: 10, owner: nil)

      _(bullet.velocity_x).must_equal Rubowar::Config::Combat::BULLET_SPEED
      _(bullet.velocity_y).must_be_close_to 0, 0.001
    end

    it "calculates velocity from angle 90 (north)" do
      bullet = Rubowar::Bullet.new(x: 0, y: 0, angle: 90, damage: 10, owner: nil)

      _(bullet.velocity_x).must_be_close_to 0, 0.001
      _(bullet.velocity_y).must_equal Rubowar::Config::Combat::BULLET_SPEED
    end

    it "calculates velocity from angle 180 (west)" do
      bullet = Rubowar::Bullet.new(x: 0, y: 0, angle: 180, damage: 10, owner: nil)

      _(bullet.velocity_x).must_equal(-Rubowar::Config::Combat::BULLET_SPEED)
      _(bullet.velocity_y).must_be_close_to 0, 0.001
    end
  end

  describe "#update" do
    it "moves bullet by velocity" do
      bullet = Rubowar::Bullet.new(x: 100, y: 100, angle: 0, damage: 10, owner: nil)

      bullet.update

      _(bullet.x).must_equal 100 + Rubowar::Config::Combat::BULLET_SPEED
      _(bullet.y).must_be_close_to 100, 0.001
    end
  end

  describe "#out_of_bounds?" do
    it "returns false when inside arena" do
      bullet = Rubowar::Bullet.new(x: 400, y: 300, angle: 0, damage: 10, owner: nil)

      _(bullet.out_of_bounds?(800, 600)).must_equal false
    end

    it "returns true when x is negative" do
      bullet = Rubowar::Bullet.new(x: -1, y: 300, angle: 0, damage: 10, owner: nil)

      _(bullet.out_of_bounds?(800, 600)).must_equal true
    end

    it "returns true when x exceeds width" do
      bullet = Rubowar::Bullet.new(x: 801, y: 300, angle: 0, damage: 10, owner: nil)

      _(bullet.out_of_bounds?(800, 600)).must_equal true
    end

    it "returns true when y is negative" do
      bullet = Rubowar::Bullet.new(x: 400, y: -1, angle: 0, damage: 10, owner: nil)

      _(bullet.out_of_bounds?(800, 600)).must_equal true
    end

    it "returns true when y exceeds height" do
      bullet = Rubowar::Bullet.new(x: 400, y: 601, angle: 0, damage: 10, owner: nil)

      _(bullet.out_of_bounds?(800, 600)).must_equal true
    end
  end
end
