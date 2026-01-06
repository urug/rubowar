# frozen_string_literal: true

module Rubowar
  # Shared cost calculations for sensing actions (probe, scan, pulse).
  # Used by both Rubot (for upfront energy checks) and Arena (for processing).
  module SensingCosts
    # Probe costs
    PROBE_BASE_COST = 0
    PROBE_ATTRIBUTE_COSTS = {
      size: 1,
      position: 4,
      velocity: 3,
      turret_angle: 2,
      shield: 2,
      health: 3,
      energy: 3
    }.freeze

    # Scan costs
    SCAN_BASE_COST = 3
    SCAN_ANGLE_DIVISOR = 20.0
    SCAN_DISTANCE_DIVISOR = 100.0
    SCAN_VELOCITY_COST = 2
    SCAN_OWNER_COST = 1

    # Pulse costs
    PULSE_BASE_COST = 2
    PULSE_DISTANCE_DIVISOR = 75.0
    PULSE_OWNER_COST = 1

    # Detect cost (counter-intelligence)
    DETECT_COST = 2

    def probe_cost(attributes)
      PROBE_BASE_COST + attributes.sum { |attr| PROBE_ATTRIBUTE_COSTS[attr] || 0 }
    end

    def scan_cost(angle:, distance:, velocity: false, owner: false)
      cost = SCAN_BASE_COST +
             (angle / SCAN_ANGLE_DIVISOR).ceil +
             (distance / SCAN_DISTANCE_DIVISOR).ceil
      cost += SCAN_VELOCITY_COST if velocity
      cost += SCAN_OWNER_COST if owner
      cost
    end

    def pulse_cost(distance:, owner: false)
      cost = PULSE_BASE_COST + (distance / PULSE_DISTANCE_DIVISOR).ceil
      cost += PULSE_OWNER_COST if owner
      cost
    end

    def detect_cost
      DETECT_COST
    end
  end
end
