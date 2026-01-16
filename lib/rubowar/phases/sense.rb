# frozen_string_literal: true

# [file]
# purpose = "Phase 1: Process all sensing actions for all rubots"
# responsibility = "Execute probe, scan, pulse, detect with fairness and latency"
# pattern = "Phase Module (module_function)"
#
# [execution_order]
# step_1 = "Reset detection counts for all actors"
# step_2 = "Process probe/scan/pulse (increments detection counts on targets)"
# step_3 = "Process detect last (reports current chronon's detection counts)"
#
# [timing]
# note = "Results available next chronon (1-chronon latency for planning)"
# exception = "detect returns current chronon counts (but read next chronon)"

module Rubowar
  module Phases
    module Sense
      module_function

      # Execute sense phase for all actors
      # Returns array of failed actions: [{ actor:, action: }, ...]
      def execute(arena:, actors:)
        failed_actions = []

        # 1. Reset detection counts (prepare for this chronon's sensing)
        actors.each(&:reset_detection_counts)

        # 2. Process probe/scan/pulse for ALL actors (increments detection counts on targets)
        actors.each do |actor|
          next if actor.dead?

          actor.rubot_actions[:sense].each do |action|
            next if action[:type] == :detect

            begin
              success = arena.process_action(actor:, action:)
              failed_actions << { actor:, action: } unless success
            rescue InvalidActionError => e
              actor.apply_damage(Config::Battle::ERROR_DAMAGE)
              failed_actions << { actor:, action:, error: e }
            end
          end
        end

        # 3. Process detect actions for ALL actors (reports this chronon's detection counts)
        # Must be a separate loop so all probe/scan/pulse from ALL actors complete first
        # rubocop:disable Style/CombinableLoops
        actors.each do |actor|
          next if actor.dead?

          actor.rubot_actions[:sense].each do |action|
            next unless action[:type] == :detect

            begin
              success = arena.process_action(actor:, action:)
              failed_actions << { actor:, action: } unless success
            rescue InvalidActionError => e
              actor.apply_damage(Config::Battle::ERROR_DAMAGE)
              failed_actions << { actor:, action:, error: e }
            end
          end
        end
        # rubocop:enable Style/CombinableLoops

        failed_actions
      end
    end
  end
end
