# frozen_string_literal: true

require "test_helper"

class LookTestBot
  include Rubowar::Rubot
  size :medium
  def tick; end
end

class SmallLookTestBot
  include Rubowar::Rubot
  size :small
  def tick; end
end

class LargeLookTestBot
  include Rubowar::Rubot
  size :large
  def tick; end
end

def build_arena
  Rubowar::Arena.new(width: 800, height: 600)
end

def build_runner(x:, y:, turret_angle: 0, klass: LookTestBot)
  runner = Rubowar::RubotRunner.new(klass)
  runner.x = x
  runner.y = y
  runner.turret_angle = turret_angle
  runner
end

describe Rubowar::Arena do
  describe "#find_rubot_in_line_of_sight" do
    it "returns nil when no other rubots exist" do
      arena = build_arena
      runner = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.instance_variable_set(:@runners, [runner])

      result = arena.send(:find_rubot_in_line_of_sight, runner)

      _(result).must_be_nil
    end

    it "returns nil when target is behind the shooter" do
      arena = build_arena
      shooter = build_runner(x: 200, y: 100, turret_angle: 0) # Facing east
      target = build_runner(x: 100, y: 100) # West of shooter
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_be_nil
    end

    it "returns target when directly in front" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0) # Facing east
      target = build_runner(x: 200, y: 100) # East of shooter
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal target
    end

    it "returns target when ray passes through radius" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0) # Facing east
      target = build_runner(x: 200, y: 110) # Slightly offset but within radius (20)
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal target
    end

    it "returns nil when target is outside ray path" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0) # Facing east
      target = build_runner(x: 200, y: 150) # Too far offset (50 > radius of 20)
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_be_nil
    end

    it "returns closest target when multiple in line" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      near_target = build_runner(x: 200, y: 100)
      far_target = build_runner(x: 400, y: 100)
      arena.instance_variable_set(:@runners, [shooter, far_target, near_target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal near_target
    end

    it "ignores dead rubots" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      dead_target = build_runner(x: 200, y: 100)
      dead_target.health = 0
      arena.instance_variable_set(:@runners, [shooter, dead_target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_be_nil
    end

    it "works with angle 90 (north)" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 90) # Facing north
      target = build_runner(x: 100, y: 200) # North of shooter
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal target
    end

    it "works with angle 180 (west)" do
      arena = build_arena
      shooter = build_runner(x: 200, y: 100, turret_angle: 180) # Facing west
      target = build_runner(x: 100, y: 100) # West of shooter
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal target
    end

    it "works with angle 270 (south)" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 200, turret_angle: 270) # Facing south
      target = build_runner(x: 100, y: 100) # South of shooter
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal target
    end

    it "works with diagonal angle 45 (northeast)" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 45)
      target = build_runner(x: 200, y: 200) # Northeast, on the 45° line
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal target
    end

    it "works with diagonal angle 135 (northwest)" do
      arena = build_arena
      shooter = build_runner(x: 200, y: 100, turret_angle: 135)
      target = build_runner(x: 100, y: 200) # Northwest
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal target
    end

    it "detects target at edge of radius" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 119) # Offset by 19, just inside radius of 20
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal target
    end

    it "misses target just outside radius" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 121) # Offset by 21, just outside radius of 20
      arena.instance_variable_set(:@runners, [shooter, target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_be_nil
    end

    it "does not detect self" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.instance_variable_set(:@runners, [shooter])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_be_nil
    end

    it "detects small rubot with radius 15" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      small_target = build_runner(x: 200, y: 114, klass: SmallLookTestBot) # Offset 14, inside radius 15
      arena.instance_variable_set(:@runners, [shooter, small_target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal small_target
    end

    it "misses small rubot outside its radius" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      small_target = build_runner(x: 200, y: 116, klass: SmallLookTestBot) # Offset 16, outside radius 15
      arena.instance_variable_set(:@runners, [shooter, small_target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_be_nil
    end

    it "detects large rubot with radius 25" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      large_target = build_runner(x: 200, y: 124, klass: LargeLookTestBot) # Offset 24, inside radius 25
      arena.instance_variable_set(:@runners, [shooter, large_target])

      result = arena.send(:find_rubot_in_line_of_sight, shooter)

      _(result).must_equal large_target
    end
  end

  describe "#build_look_result" do
    it "returns x, y, size at energy level 1" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.velocity_x = 5.0
      target.shield_level = 10
      target.health = 80
      target.energy = 60

      result = arena.send(:build_look_result, target, 1)

      _(result[:x]).must_equal 200
      _(result[:y]).must_equal 150
      _(result[:size]).must_equal :medium
      _(result.key?(:velocity_x)).must_equal false
      _(result.key?(:shield_level)).must_equal false
      _(result.key?(:health)).must_equal false
      _(result.key?(:energy)).must_equal false
    end

    it "adds velocity at energy level 2" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.velocity_x = 5.0
      target.velocity_y = -3.0

      result = arena.send(:build_look_result, target, 2)

      _(result[:velocity_x]).must_equal 5.0
      _(result[:velocity_y]).must_equal(-3.0)
      _(result.key?(:shield_level)).must_equal false
    end

    it "adds shield_level at energy level 3" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.shield_level = 25

      result = arena.send(:build_look_result, target, 3)

      _(result[:shield_level]).must_equal 25
      _(result.key?(:health)).must_equal false
    end

    it "adds health at energy level 4" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.health = 75

      result = arena.send(:build_look_result, target, 4)

      _(result[:health]).must_equal 75
      _(result.key?(:energy)).must_equal false
    end

    it "adds energy at energy level 5" do
      arena = build_arena
      target = build_runner(x: 200, y: 150)
      target.energy = 45

      result = arena.send(:build_look_result, target, 5)

      _(result[:energy]).must_equal 45
    end
  end

  describe "#process_look" do
    it "sets look result on rubot instance when target found" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      arena.instance_variable_set(:@runners, [shooter, target])

      arena.send(:process_look, shooter, 1)

      result = shooter.instance.instance_variable_get(:@_look_result)
      _(result).wont_be_nil
      _(result[:x]).must_equal 200
    end

    it "sets look result to nil when no target found" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.instance_variable_set(:@runners, [shooter])

      arena.send(:process_look, shooter, 1)

      result = shooter.instance.instance_variable_get(:@_look_result)
      _(result).must_be_nil
    end

    it "spends energy" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 50
      arena.instance_variable_set(:@runners, [shooter])

      arena.send(:process_look, shooter, 3)

      _(shooter.energy).must_equal 47
    end

    it "returns false and drains energy when insufficient" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      shooter.energy = 2
      arena.instance_variable_set(:@runners, [shooter])

      result = arena.send(:process_look, shooter, 5)

      _(result).must_equal false
      _(shooter.energy).must_equal 0
    end

    it "updates look result when target moves out of sight" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      target = build_runner(x: 200, y: 100)
      arena.instance_variable_set(:@runners, [shooter, target])

      arena.send(:process_look, shooter, 1)
      first_result = shooter.instance.instance_variable_get(:@_look_result)
      _(first_result).wont_be_nil

      target.y = 200
      arena.send(:process_look, shooter, 1)
      second_result = shooter.instance.instance_variable_get(:@_look_result)

      _(second_result).must_be_nil
    end

    it "updates look result when new target appears" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      arena.instance_variable_set(:@runners, [shooter])

      arena.send(:process_look, shooter, 1)
      first_result = shooter.instance.instance_variable_get(:@_look_result)
      _(first_result).must_be_nil

      target = build_runner(x: 200, y: 100)
      arena.instance_variable_set(:@runners, [shooter, target])
      arena.send(:process_look, shooter, 1)
      second_result = shooter.instance.instance_variable_get(:@_look_result)

      _(second_result).wont_be_nil
      _(second_result[:x]).must_equal 200
    end

    it "returns correct size for different rubot sizes" do
      arena = build_arena
      shooter = build_runner(x: 100, y: 100, turret_angle: 0)
      small_target = build_runner(x: 200, y: 100, klass: SmallLookTestBot)
      arena.instance_variable_set(:@runners, [shooter, small_target])

      arena.send(:process_look, shooter, 1)
      result = shooter.instance.instance_variable_get(:@_look_result)

      _(result[:size]).must_equal :small
    end
  end
end
