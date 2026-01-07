# frozen_string_literal: true

# [file]
# purpose = "Mixin for simple target tracking and aiming"
# responsibility = "Acquire targets from sensing, track position/velocity, aim turret with lead"
# pattern = "Mixin Module"
#
# [module.SimpleTargeting]
# purpose = "Provides common targeting logic for rubots"
# usage = "include Rubowar::SimpleTargeting in your rubot class"
# target_format = "{ x:, y:, velocity_x:, velocity_y: }"
#
# [methods]
# acquisition = ["acquire_target_from_pulse", "acquire_target_from_scan", "acquire_target_from_probe", "assign_target"]
# aiming = ["aim_turret_at_target", "turret_aligned?", "target_lead_angle", "target_lead_position"]
# state = ["target?", "target_stale?", "target_age", "target_distance", "clear_target"]

module Rubowar
  module SimpleTargeting

    def self.included(klass)
      klass.attr_accessor :targeting_target, :targeting_tick_acquired
    end

    # === Target Acquisition ===

    # Acquire closest rubot from pulse results
    # Returns true if target acquired, false otherwise
    def acquire_target_from_pulse
      return false unless pulse_result

      rubots = pulse_result.select { |t| t[:type] == :rubot }
      return false if rubots.empty?

      closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
      assign_target(closest)
      true
    end

    # Acquire closest rubot from scan results (includes velocity)
    # Returns true if target acquired, false otherwise
    def acquire_target_from_scan
      return false unless scan_result

      rubots = scan_result.select { |t| t[:type] == :rubot }
      return false if rubots.empty?

      closest = rubots.min_by { |t| distance_to(t[:x], t[:y]) }
      assign_target(closest)
      true
    end

    # Update target from probe results (most accurate)
    # Returns true if target updated, false otherwise
    def acquire_target_from_probe
      return false unless probe_result&.any?

      assign_target(probe_result)
      true
    end

    # Acquire from any available sensing result (probe > scan > pulse)
    def acquire_target_from_any
      acquire_target_from_probe || acquire_target_from_scan || acquire_target_from_pulse
    end

    # Manually set target position
    def assign_target(data)
      @targeting_target = {
        x: data[:x],
        y: data[:y],
        velocity_x: data[:velocity_x],
        velocity_y: data[:velocity_y]
      }
      @targeting_tick_acquired = tick_number
    end

    def clear_target
      @targeting_target = nil
      @targeting_tick_acquired = nil
    end

    # === Target State ===

    def target?
      !!(@targeting_target && !target_stale?)
    end

    def target_stale?
      return true unless @targeting_tick_acquired

      (tick_number - @targeting_tick_acquired) > targeting_config(:target_timeout)
    end

    def target_age
      return nil unless @targeting_tick_acquired

      tick_number - @targeting_tick_acquired
    end

    def target_distance
      return nil unless @targeting_target

      distance_to(@targeting_target[:x], @targeting_target[:y])
    end

    # === Aiming ===

    # Calculate angle to target with lead prediction
    def target_lead_angle
      return nil unless @targeting_target

      lead_angle(
        @targeting_target[:x],
        @targeting_target[:y],
        @targeting_target[:velocity_x],
        @targeting_target[:velocity_y],
        projectile_speed: targeting_config(:bullet_speed)
      )
    end

    # Calculate lead position for target
    def target_lead_position
      return nil unless @targeting_target

      lead_position(
        @targeting_target[:x],
        @targeting_target[:y],
        @targeting_target[:velocity_x],
        @targeting_target[:velocity_y],
        projectile_speed: targeting_config(:bullet_speed),
        max_lead_ticks: targeting_config(:max_lead_ticks)
      )
    end

    # Turn turret toward target (with lead), respecting max turn rate
    # Returns the angle difference (for checking alignment)
    def aim_turret_at_target
      return nil unless @targeting_target

      target_angle = target_lead_angle
      turret_diff = normalize_angle(target_angle - turret_angle)
      max_turn = targeting_config(:max_turret_turn)

      turret(turret_diff.clamp(-max_turn, max_turn))
      turret_diff
    end

    # Check if turret is aligned with target (within tolerance)
    def turret_aligned?(tolerance: nil)
      return false unless @targeting_target

      tolerance ||= targeting_config(:alignment_tolerance)
      target_angle = target_lead_angle
      turret_diff = normalize_angle(target_angle - turret_angle)

      turret_diff.abs < tolerance
    end

    # === Configuration ===

    # Override this method to customize targeting behavior
    def targeting_config(key)
      if defined?(self.class::TARGETING_CONFIG) && self.class::TARGETING_CONFIG[key]
        self.class::TARGETING_CONFIG[key]
      else
        case key
        when :bullet_speed then Config::Targeting::BULLET_SPEED
        when :max_lead_ticks then Config::Targeting::MAX_LEAD_TICKS
        when :alignment_tolerance then Config::Targeting::ALIGNMENT_TOLERANCE
        when :max_turret_turn then Config::Targeting::MAX_TURRET_TURN
        when :target_timeout then Config::Targeting::TARGET_TIMEOUT
        end
      end
    end
  end
end
