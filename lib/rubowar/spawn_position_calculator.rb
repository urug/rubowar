# frozen_string_literal: true

# [file]
# purpose = "Calculate valid spawn positions for rubots and energons"
# responsibility = "Find positions that satisfy distance constraints"
# pattern = "Module Functions (stateless calculations)"
#
# [algorithms]
# rubot_spawn = "Random position with min/max distance from existing rubots"
# energon_spawn = "Grid sampling to maximize minimum distance from all rubots"

module Rubowar
  module SpawnPositionCalculator
    module_function

    # Find a spawn position for a rubot with min/max distance constraints
    # Returns {x:, y:} position or raises SpawnError if no valid position found after max attempts
    # @raise [InvalidSpawnConstraintsError] if max_distance < min_distance
    def find_rubot_position(width:, height:, radius:, existing_positions:,
                            wall_buffer:, min_distance:, max_distance: nil)
      if max_distance && max_distance < min_distance
        raise InvalidSpawnConstraintsError,
              "max_distance (#{max_distance}) cannot be less than min_distance (#{min_distance})"
      end

      # Validate spawn area is large enough
      min_x = wall_buffer + radius
      max_x = width - wall_buffer - radius
      min_y = wall_buffer + radius
      max_y = height - wall_buffer - radius

      if min_x > max_x || min_y > max_y
        raise InvalidSpawnConstraintsError,
              "Arena too small for spawn constraints (width: #{width}, height: #{height}, " \
              "wall_buffer: #{wall_buffer}, radius: #{radius})"
      end

      Config::Spawn::MAX_ATTEMPTS.times do
        x = rand(min_x..max_x)
        y = rand(min_y..max_y)

        next if too_close?(x, y, existing_positions, min_distance)
        next if max_distance && !close_enough?(x, y, existing_positions, max_distance)

        return { x:, y: }
      end

      raise SpawnError, "Could not find valid spawn position after #{Config::Spawn::MAX_ATTEMPTS} attempts"
    end

    # Find a spawn position for energon that maximizes minimum distance from rubots
    # Uses grid sampling to find positions, returns {x:, y:} or nil if no valid position
    def find_energon_position(width:, height:, rubot_positions:, wall_buffer:)
      return { x: width / 2.0, y: height / 2.0 } if rubot_positions.empty?

      candidates = []
      best_min_distance = -1
      tolerance = Config::Spawn::ENERGON_POSITION_TOLERANCE

      # Sample candidate positions using a grid
      (wall_buffer..(width - wall_buffer)).step(Config::Spawn::ENERGON_GRID_STEP) do |cx|
        (wall_buffer..(height - wall_buffer)).step(Config::Spawn::ENERGON_GRID_STEP) do |cy|
          min_dist = rubot_positions.map do |pos|
            Physics.distance(x1: cx, y1: cy, x2: pos[:x], y2: pos[:y])
          end.min

          if min_dist > best_min_distance + tolerance
            best_min_distance = min_dist
            candidates = [{ x: cx.to_f, y: cy.to_f }]
          elsif min_dist >= best_min_distance - tolerance
            candidates << { x: cx.to_f, y: cy.to_f }
          end
        end
      end

      candidates.sample
    end

    # Check if position is too close to any existing position
    def too_close?(x, y, positions, min_distance)
      positions.any? do |pos|
        Physics.distance(x1: x, y1: y, x2: pos[:x], y2: pos[:y]) < min_distance
      end
    end

    # Check if position is close enough to at least one existing position
    def close_enough?(x, y, positions, max_distance)
      return true if positions.empty?

      positions.any? do |pos|
        Physics.distance(x1: x, y1: y, x2: pos[:x], y2: pos[:y]) <= max_distance
      end
    end
  end
end
