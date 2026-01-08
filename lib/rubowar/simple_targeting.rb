# frozen_string_literal: true

# [file]
# purpose = "Mixin for simple target tracking and aiming"
# responsibility = "Extract targets from sensing, calculate aim angles"
# pattern = "Functional Mixin"
#
# [module.SimpleTargeting]
# purpose = "Provides common targeting logic for rubots"
# usage = "include Rubowar::SimpleTargeting in your rubot class"
# target_format = "{ x:, y:, velocity_x:, velocity_y: }"
#
# [design]
# style = "Functional - methods take data, return results, no hidden side effects"
# example = """
#   self.target = acquire_target_from_probe(probe_result) || acquire_target_from_pulse(pulse_result)
#
#   if target
#     turret(aim_at_target(target))
#     fire(10) if turret_aligned?(target)
#   end
# """
#
# [methods]
# acquisition = ["acquire_target_from_pulse(result)", "acquire_target_from_scan(result)", "acquire_target_from_probe(result)"]
# aiming = ["aim_at_target(target)", "turret_aligned?(target)", "lead_angle_to(target)", "lead_position_for(target)"]
# state = ["target (attr_accessor)", "target_chronon (attr_accessor)", "target_stale?", "target_age"]

module Rubowar
  module SimpleTargeting
    def self.included(klass)
      klass.attr_accessor :target, :target_chronon
    end

    # === Target Acquisition (pure functions) ===

    # Extract target from probe result
    # @param result [Hash, nil] probe_result hash with position/velocity
    # @return [Hash, nil] normalized target or nil
    def acquire_target_from_probe(result)
      return nil unless result&.any?

      normalize_target(result)
    end

    # Extract closest rubot from scan results
    # @param result [Array, nil] scan_result array
    # @return [Hash, nil] closest rubot target or nil
    def acquire_target_from_scan(result)
      return nil unless result

      closest_rubot_from(result)
    end

    # Extract closest rubot from pulse results
    # @param result [Array, nil] pulse_result array
    # @return [Hash, nil] closest rubot target or nil
    def acquire_target_from_pulse(result)
      return nil unless result

      closest_rubot_from(result)
    end

    # === Aiming (pure functions) ===

    # Calculate turret turn angle to aim at target (with lead prediction)
    # @param target [Hash] target with x, y, velocity_x, velocity_y
    # @return [Numeric] degrees to turn turret (clamped to max turn rate)
    def aim_at_target(target)
      return 0 unless target

      target_angle = lead_angle_to(target)
      turret_diff = normalize_angle(target_angle - turret_angle)
      max_turn = targeting_config(:max_turret_turn)

      turret_diff.clamp(-max_turn, max_turn)
    end

    # Check if turret is aligned with target (within tolerance)
    # @param target [Hash] target with x, y, velocity_x, velocity_y
    # @param tolerance [Numeric, nil] alignment tolerance in degrees
    # @return [Boolean]
    def turret_aligned?(target, tolerance: nil)
      return false unless target

      tolerance ||= targeting_config(:alignment_tolerance)
      target_angle = lead_angle_to(target)
      turret_diff = normalize_angle(target_angle - turret_angle)

      turret_diff.abs < tolerance
    end

    # Calculate angle to target with lead prediction
    # @param target [Hash] target with x, y, velocity_x, velocity_y
    # @return [Numeric, nil] angle in degrees or nil
    def lead_angle_to(target)
      return nil unless target

      lead_angle(
        target[:x],
        target[:y],
        target[:velocity_x],
        target[:velocity_y],
        projectile_speed: targeting_config(:bullet_speed)
      )
    end

    # Calculate lead position for target
    # @param target [Hash] target with x, y, velocity_x, velocity_y
    # @return [Array, nil] [lead_x, lead_y] or nil
    def lead_position_for(target)
      return nil unless target

      lead_position(
        target[:x],
        target[:y],
        target[:velocity_x],
        target[:velocity_y],
        projectile_speed: targeting_config(:bullet_speed),
        max_lead_chronons: targeting_config(:max_lead_chronons)
      )
    end

    # Calculate distance to target
    # @param target [Hash] target with x, y
    # @return [Numeric, nil] distance or nil
    def distance_to_target(target)
      return nil unless target

      distance_to(target[:x], target[:y])
    end

    # === State Helpers ===

    # Check if current target is stale (requires target_chronon to be set)
    # @return [Boolean]
    def target_stale?
      return true unless @target_chronon

      (chronons - @target_chronon) > targeting_config(:target_timeout)
    end

    # Get age of current target in chronons
    # @return [Integer, nil]
    def target_age
      return nil unless @target_chronon

      chronons - @target_chronon
    end

    # === Configuration ===

    # Get targeting config value (can be overridden per-class)
    # @param key [Symbol] config key
    # @return [Numeric]
    def targeting_config(key)
      if defined?(self.class::TARGETING_CONFIG) && self.class::TARGETING_CONFIG[key]
        self.class::TARGETING_CONFIG[key]
      else
        case key
        when :bullet_speed then Config::Targeting::BULLET_SPEED
        when :max_lead_chronons then Config::Targeting::MAX_LEAD_CHRONONS
        when :alignment_tolerance then Config::Targeting::ALIGNMENT_TOLERANCE
        when :max_turret_turn then Config::Targeting::MAX_TURRET_TURN
        when :target_timeout then Config::Targeting::TARGET_TIMEOUT
        end
      end
    end

    private

    # Extract closest rubot from sensing results
    # @param results [Array] sensing results with type, x, y keys
    # @return [Hash, nil] normalized target or nil
    def closest_rubot_from(results)
      rubots = results.select { |t| t[:type] == :rubot }
      return nil if rubots.empty?

      closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
      normalize_target(closest)
    end

    # Normalize target data to consistent format
    # @param data [Hash] raw target data
    # @return [Hash] normalized target
    def normalize_target(data)
      {
        x: data[:x],
        y: data[:y],
        velocity_x: data[:velocity_x],
        velocity_y: data[:velocity_y]
      }
    end
  end
end
