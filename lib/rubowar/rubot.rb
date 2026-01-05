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
                           :turret_angle,
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

    # Thrust in the specified direction (world coordinates, 0° = east, 90° = north).
    # Energy cost is calculated based on desired speed and momentum change:
    #   base_cost = (speed / 1.5)^2
    #   actual_cost = base_cost * momentum_multiplier (1.0 to 2.0)
    #
    # If you can't afford the full thrust, you get partial thrust and energy drains to zero.
    def thrust(speed:, angle:)
      return if speed <= 0

      actions << { type: :thrust, speed: speed, angle: angle % 360 }
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

    LOOK_ATTRIBUTES = %i[size velocity shield health energy].freeze

    # Queues a look action and returns the result from the PREVIOUS tick's look.
    # Since actions are processed after tick(), the current look result won't be
    # available until the next tick. Returns nil if no previous look was performed
    # or if no target was in line of sight.
    #
    # Base look (no arguments) costs 1 energy and returns { x:, y: }.
    # Additional attributes can be requested at extra cost:
    #   :size     - 1 energy (small/medium/large)
    #   :velocity - 2 energy (velocity_x, velocity_y)
    #   :shield   - 2 energy (shield_level)
    #   :health   - 3 energy (current HP)
    #   :energy   - 3 energy (current energy)
    #
    # Examples:
    #   look                    # 1 energy  -> { x:, y: }
    #   look(:size)             # 2 energy  -> { x:, y:, size: }
    #   look(:size, :velocity)  # 4 energy  -> { x:, y:, size:, velocity_x:, velocity_y: }
    def look(*attributes)
      invalid = attributes - LOOK_ATTRIBUTES
      raise ArgumentError, "Invalid look attributes: #{invalid.join(', ')}" if invalid.any?

      actions << { type: :look, attributes: attributes }
      @_look_result
    end

    # @api private
    # Used by game engine to set/clear look results
    attr_writer :_look_result

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
