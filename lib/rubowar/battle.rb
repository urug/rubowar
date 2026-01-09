# frozen_string_literal: true

require "set"
require "timeout"

# [file]
# purpose = "Game loop orchestration for rubot battles"
# responsibility = "Chronon execution, event emission, win condition detection"
# pattern = "Game Loop / Event Emitter"
#
# [class.Battle]
# purpose = "Orchestrates a complete battle from start to finish"
# input = "Array of Rubot classes to compete"
# output = "Winner, events log, final state"
# collaborators = ["Arena", "RubotActor"]
#
# [actions]
# structure = "Hash with phase keys: { sense: [], move: [], combat: [] }"
# example = """
#   {
#     sense:  [{ type: :probe, attributes: [:position] }, { type: :detect }],
#     move:   [{ type: :thrust, speed: 5, angle: 90 }, { type: :rotate_turret, degrees: 15 }],
#     combat: [{ type: :fire, energy: 20 }, { type: :shield, energy: 10 }]
#   }
# """
# note = "Each rubot's actions hash is reset at the start of each chronon"
#
# [chronon_phases]
# order = [
#   "1. Collect actions - call each rubot's act method, which queues actions by phase",
#   "2. Phases::Sense - process actions[:sense] (probe, scan, pulse, then detect last)",
#   "3. Phases::Move - process actions[:move] (thrust, turret), then update rubot physics",
#   "4. Phases::Combat - process actions[:combat] (fire, shield), then update bullet physics",
#   "5. Phases::Energon - check collection, spawn new energons",
#   "6. Maintenance - regenerate energy, degrade shields, check for deaths"
# ]
# fairness = "All rubots queue actions first, then phases process all rubots simultaneously"
# pattern = "Each phase is a module_function module returning failed actions for event emission"
#
# [events]
# types = ["chronon", "death", "hit", "battle_end", "energon_spawn", "energon_spawn_failed", "energon_collect"]
# usage = "battle.on(:death) { |data| puts data[:actor].rubot_class.name }"

module Rubowar
  class Battle
    attr_reader :arena, :chronons, :winner, :events

    def initialize(rubot_classes, width: Config::Arena::DEFAULT_WIDTH, height: Config::Arena::DEFAULT_HEIGHT,
                   friction: Config::Arena::DEFAULT_FRICTION, chronon_limit: Config::Battle::DEFAULT_CHRONON_LIMIT)
      validate_rubot_classes!(rubot_classes)
      validate_dimensions!(width, height)
      validate_friction!(friction)
      validate_chronon_limit!(chronon_limit)

      @arena = Arena.new(width:, height:, friction:)
      @arena.spawn_rubots(rubot_classes)
      @chronons_limit = chronon_limit
      @chronons = 0
      @winner = nil
      @events = []
      @callbacks = Hash.new { |h, k| h[k] = Set.new }
    end

    def on(event_type, &block)
      @callbacks[event_type].add(block)
    end

    def run
      call_on_spawn

      loop do
        @chronons += 1

        run_chronon
        emit(:chronon, chronon_state)

        break if battle_over?
      end

      determine_winner
      emit(:battle_end, { winner: @winner, chronons: @chronons })

      @events
    end

    private

    def call_on_spawn
      @arena.actors.each do |actor|
        setup_rubot_for_chronon(actor)
        actor.call_safely(&:on_spawn)
      end
    end

    def run_chronon
      # Cache arena state once per chronon (same for all actors)
      cached_arena_state = @arena.to_state(@chronons)

      # 1. Set up state and call each rubot's act to queue actions
      @arena.actors.each do |actor|
        next if actor.dead?

        setup_rubot_for_chronon(actor, cached_arena_state)

        begin
          Timeout.timeout(Config::Battle::CHRONON_TIMEOUT) do
            actor.act
          end
        rescue Timeout::Error
          actor.apply_damage(Config::Battle::TIMEOUT_DAMAGE)
          emit(:error, { actor:, error: "Chronon timeout exceeded #{Config::Battle::CHRONON_TIMEOUT}s" })
        rescue StandardError => e
          actor.apply_damage(Config::Battle::ERROR_DAMAGE)
          emit(:error, { actor:, error: e })
        end
      end

      # 2. Process actions in phases for fairness (no spawn-order advantage)
      execute_phases

      # 3. Regenerate energy and degrade shields
      @arena.regenerate_and_degrade

      # 4. Check for deaths (only process newly dead rubots)
      @arena.actors.each do |actor|
        next unless actor.dead? && !actor.death_processed

        actor.death_processed = true
        actor.call_on_death
        emit(:death, { actor: })
      end
    end

    def execute_phases
      actors = @arena.actors

      # Phase 1: Sensing (probe, scan, pulse, then detect last)
      Phases::Sense.execute(arena: @arena, actors:).each do |failure|
        emit(:action_failed, failure)
        emit(:error, { actor: failure[:actor], error: failure[:error] }) if failure[:error]
      end

      # Phase 2: Movement (thrust, turret), then physics
      Phases::Move.execute(arena: @arena, actors:).each do |failure|
        emit(:action_failed, failure)
        emit(:error, { actor: failure[:actor], error: failure[:error] }) if failure[:error]
      end

      # Phase 3: Combat (fire, shield), then bullet physics
      Phases::Combat.execute(arena: @arena, actors:).each do |failure|
        emit(:action_failed, failure)
        emit(:error, { actor: failure[:actor], error: failure[:error] }) if failure[:error]
      end

      # Phase 4: Energon collection and spawning
      energon_result = Phases::Energon.execute(arena: @arena, chronon: @chronons)

      energon_result[:collections].each do |collection|
        emit(:energon_collect, {
               actor: collection[:actor],
               x: collection[:energon].x,
               y: collection[:energon].y,
               amount: collection[:amount]
             })
      end

      if energon_result[:spawned]
        emit(:energon_spawn, { x: energon_result[:spawned].x, y: energon_result[:spawned].y })
      elsif energon_result[:spawn_failed]
        emit(:energon_spawn_failed, { chronon: @chronons })
      end
    end

    def setup_rubot_for_chronon(actor, arena_state = nil)
      actor.rubot_state = actor.to_state
      actor.arena_state = arena_state || @arena.to_state(@chronons)
      actor.reset_actions
      # Reset pending energy spend for this chronon's upfront energy checks
      actor._pending_energy_spend = 0
      # NOTE: Do NOT clear probe_echo, scan_echo, pulse_echo here.
      # They contain results from the PREVIOUS chronon's sensing actions,
      # which rubots need to read during the current chronon.
    end

    def battle_over?
      alive_actors = @arena.actors.count(&:alive?)
      alive_actors <= 1 || @chronons >= @chronons_limit
    end

    def determine_winner
      alive_actors = @arena.actors.select(&:alive?)

      @winner = if alive_actors.size == 1
                  alive_actors.first
                elsif alive_actors.empty?
                  nil
                else
                  # Tiebreaker: most damage dealt, then highest HP %
                  alive_actors.max_by { |r| [r.damage_dealt, r.health.to_f / r.max_health] }
                end
    end

    def chronon_state
      {
        chronons: @chronons,
        actors: @arena.actors.map(&:to_state),
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

    def validate_chronon_limit!(chronon_limit)
      raise InvalidChrononLimitError, "chronon_limit must be positive" unless chronon_limit.positive?
      raise InvalidChrononLimitError, "chronon_limit must be finite" if chronon_limit.respond_to?(:infinite?) && chronon_limit.infinite?
    end
  end
end
