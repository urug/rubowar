# frozen_string_literal: true

require_relative "../test_helper"
require "prop_check"

# SensorCalculator is a pure cost-calculation helper. It does not validate
# its inputs — the engine seams (Arena#process_scan, #process_pulse) call
# NumericValidation before passing values here. These properties verify the
# cost contract for the *valid* input space.
class SensorCalculatorPropertiesTest < Minitest::Test
  G = PropCheck::Generators

  def test_probe_cost_is_at_least_base
    valid_attr = G.one_of(*Rubowar::Config::Sensing::PROBE_ATTRIBUTE_COSTS.keys.map { |k| G.constant(k) })
    PropCheck.forall(G.array(valid_attr)) do |attrs|
      cost = Rubowar::SensorCalculator.probe_cost(attrs)
      assert cost >= Rubowar::Config::Sensing::PROBE_BASE_COST,
             "probe_cost(#{attrs.inspect}) = #{cost}"
    end
  end

  def test_scan_cost_is_at_least_base_for_valid_inputs
    non_neg = G.float.where { |f| f.finite? && f >= 0 && f < 10_000 }
    PropCheck.forall(non_neg, non_neg, G.boolean, G.boolean) do |angle, distance, vel, owner|
      cost = Rubowar::SensorCalculator.scan_cost(angle:, distance:, velocity: vel, owner:)
      assert cost >= Rubowar::Config::Sensing::SCAN_BASE_COST,
             "scan_cost(angle=#{angle}, distance=#{distance}) = #{cost}"
    end
  end

  def test_pulse_cost_is_at_least_base_for_valid_inputs
    non_neg = G.float.where { |f| f.finite? && f >= 0 && f < 10_000 }
    PropCheck.forall(non_neg, G.boolean) do |distance, owner|
      cost = Rubowar::SensorCalculator.pulse_cost(distance:, owner:)
      assert cost >= Rubowar::Config::Sensing::PULSE_BASE_COST,
             "pulse_cost(distance=#{distance}) = #{cost}"
    end
  end
end
