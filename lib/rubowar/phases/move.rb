# frozen_string_literal: true

# [file]
# purpose = "Phase 2: Process all movement actions and physics"
# responsibility = "Execute thrust, turret rotation, then update positions and collisions"
# pattern = "Phase Module (module_function)"
#
# [execution_order]
# step_1 = "Process all thrust and rotate_turret actions for all actors"
# step_2 = "Apply physics: friction, movement, wall collisions, rubot collisions"
#
# [fairness]
# note = "All rubots queue actions, then move simultaneously to prevent spawn-order advantage"

module Rubowar
  module Phases
    module Move
      module_function

      # Execute move phase for all actors
      # Returns array of failed actions: [{ actor:, action: }, ...]
      def execute(arena:, actors:)
        failed_actions = []

        actors.each do |actor|
          next if actor.dead?

          actor.rubot_actions[:move].each do |action|
            begin
              success = arena.process_action(actor:, action:)
              failed_actions << { actor:, action:, reason: :insufficient_energy } unless success
            rescue StandardError => e
              actor.apply_damage(Config::Battle::ERROR_DAMAGE)
              failed_actions << { actor:, action:, reason: :error, error: e }
            end
          end
        end

        arena.update_rubot_physics

        failed_actions
      end
    end
  end
end
