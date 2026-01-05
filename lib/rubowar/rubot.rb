# frozen_string_literal: true

require "forwardable"

module Rubowar
  module Rubot
    def self.included(klass)
      klass.extend(ClassMethods)
      klass.extend(Forwardable)

      # State accessors for game to set, rubots to read
      klass.attr_accessor :rubot_state, :arena_state, :actions

      # Delegate rubot state accessors
      klass.def_delegators :rubot_state,
                           :x, :y, :velocity_x, :velocity_y, :speed,
                           :body_angle, :turret_angle,
                           :health, :energy, :shield_level,
                           :damage_dealt, :damage_taken, :size

      # Delegate arena state accessors
      klass.def_delegators :arena_state,
                           :arena_width, :arena_height, :friction, :tick_number, :energons
    end

    module ClassMethods
      def size(value = nil)
        if value
          unless RubotRunner::SIZES.key?(value)
            raise ArgumentError, "Invalid size: #{value}. Must be one of: #{RubotRunner::SIZES.keys.join(', ')}"
          end

          @_size = value
        else
          @_size || :medium
        end
      end
    end

    # Action methods (queue for execution after tick)
    def thrust(energy_amount)
      return if energy_amount <= 0

      actions << { type: :thrust, energy: energy_amount }
    end

    def turn(degrees)
      degrees = normalize_degrees(degrees)
      return if degrees == 0

      actions << { type: :turn, degrees: degrees }
    end

    def turret(degrees)
      degrees = normalize_degrees(degrees)
      return if degrees == 0

      actions << { type: :turret, degrees: degrees }
    end

    def fire(energy_amount)
      return if energy_amount <= 0

      actions << { type: :fire, energy: energy_amount }
    end

    def shield(energy_amount)
      return if energy_amount <= 0

      actions << { type: :shield, energy: energy_amount }
    end

    def look(energy_level = 1)
      energy_level = energy_level.clamp(1, 5)
      actions << { type: :look, energy: energy_level }
      @_look_result
    end

    # Callbacks (override in rubot class)
    def on_spawn; end
    def on_hit(damage, direction); end
    def on_death; end
    def on_wall; end
    def on_collision(other_rubot); end
    def on_energon(amount); end

    # Required method for rubots to implement
    def tick
      raise NotImplementedError, "Rubot must implement #tick method"
    end

    private

    # Normalize degrees to -180..180 range (shortest turn)
    def normalize_degrees(degrees)
      degrees = degrees % 360
      degrees -= 360 if degrees > 180
      degrees += 360 if degrees < -180
      degrees
    end
  end
end
