# frozen_string_literal: true

# [file]
# purpose = "Shared sensor cost calculations"
# responsibility = "Single source of truth for probe, scan, and pulse energy costs"
# pattern = "Module Functions (stateless calculations)"
#
# [module.SensorCalculations]
# purpose = "Provides cost calculations used by both Rubot (upfront checks) and Arena (execution)"
# usage = "SensorCalculations.probe_cost(attributes), SensorCalculations.scan_cost(...), etc."

module Rubowar
  module SensorCalculations
    module_function

    def probe_cost(attributes)
      Config::Sensing::PROBE_BASE_COST + attributes.sum { |attr| Config::Sensing::PROBE_ATTRIBUTE_COSTS[attr] || 0 }
    end

    def scan_cost(angle:, distance:, velocity: false, owner: false)
      cost = Config::Sensing::SCAN_BASE_COST +
             (angle / Config::Sensing::SCAN_ANGLE_DIVISOR).ceil +
             (distance / Config::Sensing::SCAN_DISTANCE_DIVISOR).ceil
      cost += Config::Sensing::SCAN_VELOCITY_COST if velocity
      cost += Config::Sensing::SCAN_OWNER_COST if owner
      cost
    end

    def pulse_cost(distance:, owner: false)
      cost = Config::Sensing::PULSE_BASE_COST + (distance / Config::Sensing::PULSE_DISTANCE_DIVISOR).ceil
      cost += Config::Sensing::PULSE_OWNER_COST if owner
      cost
    end

    def detect_cost
      Config::Sensing::DETECT_COST
    end
  end
end
