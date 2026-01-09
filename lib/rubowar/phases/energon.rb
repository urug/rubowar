# frozen_string_literal: true

# [file]
# purpose = "Phase 4: Process energon collection and spawning"
# responsibility = "Check for collection, spawn new energons at interval"
# pattern = "Phase Module (module_function)"
#
# [execution_order]
# step_1 = "Check for energon collection (after movement phase)"
# step_2 = "Spawn new energon every ENERGON_SPAWN_INTERVAL chronons"
#
# [spawn_logic]
# position = "Maximizes minimum distance from all live rubots"
# timing = "Every 50 chronons (configurable)"

module Rubowar
  module Phases
    module Energon
      module_function

      # Execute energon phase
      # Returns hash with collections, spawned energon, and spawn failure indicator:
      #   { collections: [{ actor:, energon:, amount: }, ...], spawned: Energon|nil, spawn_failed: bool }
      def execute(arena:, chronon:)
        # Check for collections (after movement)
        collections = arena.check_energon_collection(chronon)

        # Spawn new energon every ENERGON_SPAWN_INTERVAL chronons
        spawn_attempted = (chronon % Config::Arena::ENERGON_SPAWN_INTERVAL).zero?
        spawned = spawn_attempted ? arena.spawn_energon(chronon) : nil
        spawn_failed = spawn_attempted && spawned.nil?

        { collections:, spawned:, spawn_failed: }
      end
    end
  end
end
