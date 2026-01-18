# frozen_string_literal: true

# [file]
# purpose = "Phase 3: Process all combat actions and bullet physics"
# responsibility = "Execute fire, shields, then update bullet positions and hits"
# pattern = "Phase Module (module_function)"
#
# [execution_order]
# step_1 = "Process all fire and raise_shields actions for all actors"
# step_2 = "Apply bullet physics: movement, collision detection, damage application"
#
# [timing]
# note = "Bullets spawn at post-movement positions (move then shoot)"

module Rubowar
  module Phases
    module Combat
      module_function

      # Execute combat phase for all actors
      # Returns array of failed actions: [{ actor:, action: }, ...]
      def execute(arena:, actors:)
        failed_actions = []

        actors.each do |actor|
          next if actor.dead?

          actor.rubot_actions[:combat].each do |action|
            begin
              success = arena.process_action(actor:, action:)
              failed_actions << { actor:, action:, reason: :insufficient_energy } unless success
            rescue StandardError => e
              actor.apply_damage(Config::Battle::ERROR_DAMAGE)
              failed_actions << { actor:, action:, reason: :error, error: e }
            end
          end
        end

        arena.update_bullet_physics

        failed_actions
      end
    end
  end
end
