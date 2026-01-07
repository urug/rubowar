# frozen_string_literal: true

# [file]
# purpose = "Shared cost calculations for sensing actions"
# responsibility = "Calculate energy costs for probe, scan, pulse, detect"
# pattern = "Mixin Module"
#
# [module.SensingCosts]
# purpose = "DRY cost calculations used by both Rubot and Arena"
# usage = "Rubot checks upfront if it can afford; Arena deducts when processing"
#
# [costs]
# probe = "0 base + 1-4 per attribute (size=1, position=4, velocity=3, health=3, etc.)"
# scan = "3 base + ceil(angle/20) + ceil(distance/100) [+2 velocity] [+1 owner]"
# pulse = "2 base + ceil(distance/75) [+1 owner]"
# detect = "2 flat"

module Rubowar
  module SensingCosts
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
