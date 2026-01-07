# frozen_string_literal: true

require "timeout"

# [file]
# purpose = "Game loop orchestration for rubot battles"
# responsibility = "Tick execution, event emission, win condition detection"
# pattern = "Game Loop / Event Emitter"
#
# [class.Battle]
# purpose = "Orchestrates a complete battle from start to finish"
# input = "Array of Rubot classes to compete"
# output = "Winner, events log, final state"
# collaborators = ["Arena", "RubotRunner"]
#
# [tick_phases]
# order = [
#   "1. Collect actions from all rubots (call tick method)",
#   "2. Process sensing actions (probe, scan, pulse, detect)",
#   "3. Process movement actions (thrust, turret)",
#   "4. Process combat actions (fire, shield)",
#   "5. Update physics (bullets, collisions, friction)",
#   "6. Check win conditions"
# ]
# fairness = "Actions processed in phases to prevent spawn-order advantage"
#
# [events]
# types = ["tick", "death", "hit", "battle_end"]
# usage = "battle.on(:death) { |data| puts data[:runner].rubot_class.name }"

module Rubowar
  class Battle
    attr_reader :arena, :tick_number, :winner, :events

    def initialize(rubot_classes, width: Config::Arena::DEFAULT_WIDTH, height: Config::Arena::DEFAULT_HEIGHT,
                   friction: Config::Arena::DEFAULT_FRICTION, tick_limit: Config::Battle::DEFAULT_TICK_LIMIT)
      validate_rubot_classes!(rubot_classes)
      validate_dimensions!(width, height)
      validate_friction!(friction)
      validate_tick_limit!(tick_limit)

      @arena = Arena.new(width:, height:, friction:)
      @arena.spawn_rubots(rubot_classes)
      @tick_limit = tick_limit
      @tick_number = 0
      @winner = nil
      @events = []
      @callbacks = Hash.new { |h, k| h[k] = [] }
    end

    def on(event_type, &block)
      @callbacks[event_type] << block
    end

    def run
      call_on_spawn

      loop do
        @tick_number += 1

        run_tick
        emit(:tick, tick_state)

        break if battle_over?
      end

      determine_winner
      emit(:battle_end, { winner: @winner, tick_number: @tick_number })

      @events
    end

    private

    def call_on_spawn
      @arena.runners.each do |runner|
        setup_rubot_for_tick(runner)
        runner.instance.on_spawn
      end
    end

    def run_tick
      # 1. Set up state and call each rubot's tick to queue actions
      @arena.runners.each do |runner|
        next if runner.dead?

        setup_rubot_for_tick(runner)

        begin
          Timeout.timeout(Config::Battle::TICK_TIMEOUT) do
            runner.instance.tick
          end
        rescue Timeout::Error
          runner.apply_damage(Config::Battle::TIMEOUT_DAMAGE)
          emit(:error, { runner:, error: "Tick timeout exceeded #{Config::Battle::TICK_TIMEOUT}s" })
        rescue StandardError => e
          runner.apply_damage(Config::Battle::ERROR_DAMAGE)
          emit(:error, { runner:, error: e })
        end
      end

      # 2. Process actions in phases for fairness (no spawn-order advantage)
      process_sense_phase
      process_move_phase
      process_combat_phase

      # 3. Process energons (collection after movement, then spawning)
      process_energon_phase

      # 4. Regenerate energy and degrade shields
      @arena.regenerate_and_degrade

      # 5. Check for deaths
      @arena.runners.each do |runner|
        next unless runner.dead?

        runner.instance.on_death
        emit(:death, { runner: })
      end
    end

    # Phase 1: All sensing actions (probe, scan, pulse, detect)
    # Detect is processed last so it reports current tick's detection counts
    def process_sense_phase
      # 1a. Reset detection counts (prepare for this tick's sensing)
      @arena.runners.each(&:reset_detection_counts)

      # 1b. Process probe/scan/pulse (increments detection counts on targets)
      @arena.runners.each do |runner|
        next if runner.dead?

        runner.instance.actions.each do |action|
          next unless %i[probe scan pulse].include?(action[:type])

          success = @arena.process_action(runner:, action:)
          emit(:action_failed, { runner:, action: }) unless success
        end
      end

      # 1c. Process detect actions last (reports this tick's detection counts)
      # rubocop:disable Style/CombinableLoops -- detect must run AFTER all sensing completes
      @arena.runners.each do |runner|
        next if runner.dead?

        runner.instance.actions.each do |action|
          next unless action[:type] == :detect

          success = @arena.process_action(runner:, action:)
          emit(:action_failed, { runner:, action: }) unless success
        end
      end
      # rubocop:enable Style/CombinableLoops
    end

    # Phase 2: All movement actions (thrust, turret), then rubot physics
    # Rubots move simultaneously, then collisions are resolved
    def process_move_phase
      @arena.runners.each do |runner|
        next if runner.dead?

        runner.instance.actions.each do |action|
          next unless %i[thrust turret].include?(action[:type])

          success = @arena.process_action(runner:, action:)
          emit(:action_failed, { runner:, action: }) unless success
        end
      end

      @arena.update_rubot_physics
    end

    # Phase 3: All combat actions (fire, shield), then bullet physics
    # Bullets spawn from post-movement positions, then move and hit
    def process_combat_phase
      @arena.runners.each do |runner|
        next if runner.dead?

        actions = runner.instance.actions
        actions.each do |action|
          next unless %i[fire shield].include?(action[:type])

          success = @arena.process_action(runner:, action:)
          emit(:action_failed, { runner:, action: }) unless success
        end
        actions.clear
      end

      @arena.update_bullet_physics
    end

    # Phase 4: Energon collection and spawning
    def process_energon_phase
      # Check for collections (after movement)
      collections = @arena.check_energon_collection(@tick_number)
      collections.each do |collection|
        emit(:energon_collect, {
               runner: collection[:runner],
               x: collection[:energon].x,
               y: collection[:energon].y,
               amount: collection[:amount]
             })
      end

      # Spawn new energon every ENERGON_SPAWN_INTERVAL ticks
      return unless (@tick_number % Config::Arena::ENERGON_SPAWN_INTERVAL).zero?

      energon = @arena.spawn_energon(@tick_number)
      emit(:energon_spawn, { x: energon.x, y: energon.y }) if energon
    end

    def setup_rubot_for_tick(runner)
      runner.instance.rubot_state = runner.to_state
      runner.instance.arena_state = @arena.to_state(@tick_number)
      runner.instance.actions ||= []
      # Reset pending energy spend for this tick's upfront energy checks
      runner.instance._pending_energy_spend = 0
      # NOTE: Do NOT clear probe_result, scan_result, pulse_result here.
      # They contain results from the PREVIOUS tick's sensing actions,
      # which rubots need to read during the current tick.
    end

    def battle_over?
      alive_runners = @arena.runners.count(&:alive?)
      alive_runners <= 1 || @tick_number >= @tick_limit
    end

    def determine_winner
      alive_runners = @arena.runners.select(&:alive?)

      @winner = if alive_runners.size == 1
                  alive_runners.first
                elsif alive_runners.empty?
                  nil
                else
                  # Tiebreaker: most damage dealt, then highest HP
                  alive_runners.max_by { |r| [r.damage_dealt, r.health] }
                end
    end

    def tick_state
      {
        tick_number: @tick_number,
        runners: @arena.runners.map(&:to_state),
        bullets: @arena.bullets.map { |b| { x: b.x, y: b.y, velocity_x: b.velocity_x, velocity_y: b.velocity_y } }
      }
    end

    def emit(event_type, data)
      event = { type: event_type, **data }
      @events << event
      @callbacks[event_type].each { |callback| callback.call(data) }
    end

    def validate_rubot_classes!(rubot_classes)
      raise InsufficientRubotsError, "need at least 2 rubots for a battle" if rubot_classes.size < 2
    end

    def validate_dimensions!(width, height)
      raise InvalidDimensionsError, "width must be positive" unless width.positive?
      raise InvalidDimensionsError, "height must be positive" unless height.positive?
    end

    def validate_friction!(friction)
      raise InvalidFrictionError, "friction must be between 0 and 1" unless (0..1).cover?(friction)
    end

    def validate_tick_limit!(tick_limit)
      raise InvalidTickLimitError, "tick_limit must be positive" unless tick_limit.positive?
    end
  end
end
