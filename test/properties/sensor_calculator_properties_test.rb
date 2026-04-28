# frozen_string_literal: true

require_relative "../test_helper"
require "prop_check"

class SensorCalculatorPropertiesTest < Minitest::Test
  G = PropCheck::Generators

  def test_probe_cost_is_at_least_base
    PropCheck.forall(G.array(G.one_of(*Rubowar::Config::Sensing::PROBE_ATTRIBUTE_COSTS.keys.map { |k| G.constant(k) }))) do |attrs|
      cost = Rubowar::SensorCalculator.probe_cost(attrs)
      assert cost >= Rubowar::Config::Sensing::PROBE_BASE_COST,
             "probe_cost(#{attrs.inspect}) = #{cost}"
    end
  end

  # scan_cost / pulse_cost are documented for non-negative angle/distance.
  # If players (or callers that forgot to validate) pass negatives, the
  # function happily returns a cost that is *lower than the base cost* —
  # potentially zero or negative — because `(neg / divisor).ceil` is a small
  # negative number. That's a correctness/abuse concern.
  def test_scan_cost_is_at_least_base_for_non_negative_inputs
    non_neg = G.float.where { |f| f.finite? && f >= 0 && f < 10_000 }
    PropCheck.forall(non_neg, non_neg, G.boolean, G.boolean) do |angle, distance, vel, owner|
      cost = Rubowar::SensorCalculator.scan_cost(
        angle:, distance:, velocity: vel, owner:
      )
      assert cost >= Rubowar::Config::Sensing::SCAN_BASE_COST,
             "scan_cost(angle=#{angle}, distance=#{distance}) = #{cost}"
    end
  end

  def test_scan_cost_rejects_or_floors_negative_inputs
    cost = Rubowar::SensorCalculator.scan_cost(angle: -10_000, distance: -10_000)
    assert cost >= 0, "scan_cost with negatives returned #{cost} — should be floored or rejected"
  end

  def test_pulse_cost_rejects_or_floors_negative_distance
    cost = Rubowar::SensorCalculator.pulse_cost(distance: -10_000)
    assert cost >= 0, "pulse_cost(distance: -10000) = #{cost}"
  end
end
