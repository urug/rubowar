# frozen_string_literal: true

require "test_helper"

describe Rubowar::SensorCalculator do
  describe ".probe_cost" do
    it "returns base cost for empty attributes" do
      cost = Rubowar::SensorCalculator.probe_cost([])

      _(cost).must_equal 0
    end

    it "returns 1 for size attribute" do
      cost = Rubowar::SensorCalculator.probe_cost([:size])

      _(cost).must_equal 1
    end

    it "returns 4 for position attribute" do
      cost = Rubowar::SensorCalculator.probe_cost([:position])

      _(cost).must_equal 4
    end

    it "sums costs for multiple attributes" do
      cost = Rubowar::SensorCalculator.probe_cost(%i[size position velocity])

      _(cost).must_equal 8 # 1 + 4 + 3
    end
  end

  describe ".scan_cost" do
    it "calculates base cost plus angle and distance" do
      cost = Rubowar::SensorCalculator.scan_cost(angle: 20, distance: 100)

      _(cost).must_equal 5 # 3 base + 1 (20/20) + 1 (100/100)
    end

    it "adds velocity cost when requested" do
      cost = Rubowar::SensorCalculator.scan_cost(angle: 20, distance: 100, velocity: true)

      _(cost).must_equal 7 # 5 + 2
    end

    it "adds owner cost when requested" do
      cost = Rubowar::SensorCalculator.scan_cost(angle: 20, distance: 100, owner: true)

      _(cost).must_equal 6 # 5 + 1
    end

    it "adds both velocity and owner costs" do
      cost = Rubowar::SensorCalculator.scan_cost(angle: 20, distance: 100, velocity: true, owner: true)

      _(cost).must_equal 8 # 5 + 2 + 1
    end

    it "uses ceiling for angle divisor" do
      cost = Rubowar::SensorCalculator.scan_cost(angle: 21, distance: 100)

      _(cost).must_equal 6 # 3 + 2 (ceil 21/20) + 1
    end

    it "uses ceiling for distance divisor" do
      cost = Rubowar::SensorCalculator.scan_cost(angle: 20, distance: 101)

      _(cost).must_equal 6 # 3 + 1 + 2 (ceil 101/100)
    end
  end

  describe ".pulse_cost" do
    it "calculates base cost plus distance" do
      cost = Rubowar::SensorCalculator.pulse_cost(distance: 75)

      _(cost).must_equal 3 # 2 base + 1 (75/75)
    end

    it "adds owner cost when requested" do
      cost = Rubowar::SensorCalculator.pulse_cost(distance: 75, owner: true)

      _(cost).must_equal 4 # 3 + 1
    end

    it "uses ceiling for distance divisor" do
      cost = Rubowar::SensorCalculator.pulse_cost(distance: 76)

      _(cost).must_equal 4 # 2 + 2 (ceil 76/75)
    end

    it "scales with longer distance" do
      cost = Rubowar::SensorCalculator.pulse_cost(distance: 200)

      _(cost).must_equal 5 # 2 + 3 (ceil 200/75)
    end
  end

  describe ".detect_cost" do
    it "returns the detect cost constant" do
      cost = Rubowar::SensorCalculator.detect_cost

      _(cost).must_equal 2
    end
  end
end
