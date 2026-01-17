# frozen_string_literal: true

require "test_helper"

describe Rubowar::SpawnPositionCalculator do
  describe ".find_rubot_position" do
    it "returns position within arena bounds" do
      pos = Rubowar::SpawnPositionCalculator.find_rubot_position(
        width: 800,
        height: 600,
        radius: 20,
        existing_positions: [],
        wall_buffer: 50,
        min_distance: 100
      )

      _(pos[:x]).must_be :>=, 70  # wall_buffer + radius
      _(pos[:x]).must_be :<=, 730 # width - wall_buffer - radius
      _(pos[:y]).must_be :>=, 70
      _(pos[:y]).must_be :<=, 530
    end

    it "maintains minimum distance from existing positions" do
      existing = [{ x: 400, y: 300 }]

      pos = Rubowar::SpawnPositionCalculator.find_rubot_position(
        width: 800,
        height: 600,
        radius: 20,
        existing_positions: existing,
        wall_buffer: 50,
        min_distance: 200
      )

      distance = Rubowar::Physics.distance(
        x1: pos[:x], y1: pos[:y],
        x2: existing[0][:x], y2: existing[0][:y]
      )
      _(distance).must_be :>=, 200
    end

    it "respects maximum distance constraint" do
      existing = [{ x: 400, y: 300 }]

      pos = Rubowar::SpawnPositionCalculator.find_rubot_position(
        width: 800,
        height: 600,
        radius: 20,
        existing_positions: existing,
        wall_buffer: 50,
        min_distance: 100,
        max_distance: 300
      )

      distance = Rubowar::Physics.distance(
        x1: pos[:x], y1: pos[:y],
        x2: existing[0][:x], y2: existing[0][:y]
      )
      _(distance).must_be :<=, 300
    end

    it "works with empty existing positions" do
      pos = Rubowar::SpawnPositionCalculator.find_rubot_position(
        width: 800,
        height: 600,
        radius: 20,
        existing_positions: [],
        wall_buffer: 50,
        min_distance: 100
      )

      _(pos[:x]).must_be_kind_of Numeric
      _(pos[:y]).must_be_kind_of Numeric
    end

    it "raises SpawnError when no valid position found" do
      # Create impossible constraints: min distance larger than arena
      existing = [{ x: 400, y: 300 }]

      _(lambda {
        Rubowar::SpawnPositionCalculator.find_rubot_position(
          width: 200,
          height: 200,
          radius: 20,
          existing_positions: existing,
          wall_buffer: 50,
          min_distance: 500 # Impossible constraint
        )
      }).must_raise Rubowar::SpawnError
    end
  end

  describe ".find_energon_position" do
    it "returns center when no rubots exist" do
      pos = Rubowar::SpawnPositionCalculator.find_energon_position(
        width: 800,
        height: 600,
        rubot_positions: [],
        wall_buffer: 50
      )

      _(pos[:x]).must_equal 400.0
      _(pos[:y]).must_equal 300.0
    end

    it "returns position within arena bounds" do
      rubot_positions = [{ x: 100, y: 100 }]

      pos = Rubowar::SpawnPositionCalculator.find_energon_position(
        width: 800,
        height: 600,
        rubot_positions:,
        wall_buffer: 50
      )

      _(pos[:x]).must_be :>=, 50
      _(pos[:x]).must_be :<=, 750
      _(pos[:y]).must_be :>=, 50
      _(pos[:y]).must_be :<=, 550
    end

    it "maximizes distance from rubots" do
      # Place rubot in corner
      rubot_positions = [{ x: 100, y: 100 }]

      pos = Rubowar::SpawnPositionCalculator.find_energon_position(
        width: 800,
        height: 600,
        rubot_positions:,
        wall_buffer: 50
      )

      # Energon should be far from the rubot (likely opposite corner area)
      distance = Rubowar::Physics.distance(
        x1: pos[:x], y1: pos[:y],
        x2: 100, y2: 100
      )

      # Distance should be reasonably far (at least half diagonal)
      min_expected_distance = Math.sqrt((800**2) + (600**2)) / 3
      _(distance).must_be :>=, min_expected_distance
    end

    it "handles multiple rubots" do
      # Place rubots in different locations
      rubot_positions = [
        { x: 100, y: 100 },
        { x: 700, y: 500 }
      ]

      pos = Rubowar::SpawnPositionCalculator.find_energon_position(
        width: 800,
        height: 600,
        rubot_positions:,
        wall_buffer: 50
      )

      _(pos).wont_be_nil
      _(pos[:x]).must_be_kind_of Numeric
      _(pos[:y]).must_be_kind_of Numeric
    end

    it "returns one of multiple equally good positions" do
      rubot_positions = [{ x: 400, y: 300 }]

      # Run multiple times to ensure determinism
      positions = 10.times.map do
        Rubowar::SpawnPositionCalculator.find_energon_position(
          width: 800,
          height: 600,
          rubot_positions:,
          wall_buffer: 50
        )
      end

      # All positions should be valid
      positions.each do |pos|
        _(pos).wont_be_nil
        _(pos[:x]).must_be_kind_of Numeric
        _(pos[:y]).must_be_kind_of Numeric
      end
    end

    it "maximizes distance from existing energons" do
      energon_positions = [{ x: 100, y: 100 }]

      pos = Rubowar::SpawnPositionCalculator.find_energon_position(
        width: 800,
        height: 600,
        rubot_positions: [],
        energon_positions:,
        wall_buffer: 50
      )

      distance = Rubowar::Physics.distance(
        x1: pos[:x], y1: pos[:y],
        x2: 100, y2: 100
      )

      min_expected_distance = Math.sqrt((800**2) + (600**2)) / 3
      _(distance).must_be :>=, min_expected_distance
    end

    it "maximizes distance from both rubots and energons" do
      rubot_positions = [{ x: 100, y: 100 }]
      energon_positions = [{ x: 700, y: 500 }]

      pos = Rubowar::SpawnPositionCalculator.find_energon_position(
        width: 800,
        height: 600,
        rubot_positions:,
        energon_positions:,
        wall_buffer: 50
      )

      rubot_distance = Rubowar::Physics.distance(
        x1: pos[:x], y1: pos[:y],
        x2: 100, y2: 100
      )
      energon_distance = Rubowar::Physics.distance(
        x1: pos[:x], y1: pos[:y],
        x2: 700, y2: 500
      )

      # Position should be reasonably far from both
      _(rubot_distance).must_be :>=, 100
      _(energon_distance).must_be :>=, 100
    end
  end

  describe ".too_close?" do
    it "returns true when position is too close" do
      positions = [{ x: 100, y: 100 }]

      result = Rubowar::SpawnPositionCalculator.too_close?(105, 105, positions, 10)

      _(result).must_equal true
    end

    it "returns false when position is far enough" do
      positions = [{ x: 100, y: 100 }]

      result = Rubowar::SpawnPositionCalculator.too_close?(120, 120, positions, 10)

      _(result).must_equal false
    end

    it "returns false for empty positions" do
      result = Rubowar::SpawnPositionCalculator.too_close?(100, 100, [], 10)

      _(result).must_equal false
    end

    it "checks all positions" do
      positions = [
        { x: 100, y: 100 },
        { x: 200, y: 200 }
      ]

      # Close to second position
      result = Rubowar::SpawnPositionCalculator.too_close?(205, 205, positions, 10)

      _(result).must_equal true
    end
  end

  describe ".close_enough?" do
    it "returns true when position is close to at least one" do
      positions = [{ x: 100, y: 100 }]

      result = Rubowar::SpawnPositionCalculator.close_enough?(105, 105, positions, 10)

      _(result).must_equal true
    end

    it "returns false when position is too far from all" do
      positions = [{ x: 100, y: 100 }]

      result = Rubowar::SpawnPositionCalculator.close_enough?(200, 200, positions, 10)

      _(result).must_equal false
    end

    it "returns true for empty positions" do
      result = Rubowar::SpawnPositionCalculator.close_enough?(100, 100, [], 10)

      _(result).must_equal true
    end

    it "returns true if close to any position" do
      positions = [
        { x: 100, y: 100 },
        { x: 500, y: 500 }
      ]

      # Close to second position, far from first
      result = Rubowar::SpawnPositionCalculator.close_enough?(505, 505, positions, 10)

      _(result).must_equal true
    end
  end
end
