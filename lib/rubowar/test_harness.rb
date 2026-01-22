# frozen_string_literal: true

# [file]
# purpose = "Test harness for rapid rubot development and debugging"
# responsibility = "Provide simple API to test rubots against dummy opponents"
# pattern = "Testing Utility"
#
# [module.TestHarness]
# purpose = "Quick way to test a rubot against various opponent types"
# usage = "Rubowar.test_battle(MyBot, opponents: [:stationary, :spinner])"
#
# [dummy_opponents]
# stationary = "Does nothing, sits still - good for testing basic mechanics"
# spinner = "Spins turret and fires - tests dodging and return fire"
# chaser = "Moves toward nearest enemy - tests evasion"
# random = "Random movement and firing - unpredictable opponent"
# shielder = "Raises shields constantly - tests sustained damage"

module Rubowar
  # Dummy opponent: does absolutely nothing
  class StationaryBot
    include Rubot
    def act; end
  end

  # Dummy opponent: spins turret and fires when it has energy
  class SpinnerBot
    include Rubot

    def act
      rotate_turret(15)
      fire(10) if energy > 30
    end
  end

  # Dummy opponent: chases nearest enemy and fires
  class ChaserBot
    include Rubot
    include SimpleTargeting

    def act
      acquire_target
      if target
        aim_at_target
        move_toward_target(thrust_speed: 4)
        fire(15) if energy > 40 && target_in_sight?(tolerance: 10)
      end
    end
  end

  # Dummy opponent: random movement and occasional firing
  class RandomBot
    include Rubot

    def act
      thrust(speed: rand(1..5), angle: rand(0..359)) if rand < 0.3
      rotate_turret(rand(-30..30)) if rand < 0.5
      fire(rand(5..15)) if energy > 50 && rand < 0.2
    end
  end

  # Dummy opponent: focuses on shields and occasional shots
  class ShielderBot
    include Rubot

    def act
      raise_shields(20) if energy > 40
      fire(10) if energy > 70
      rotate_turret(5)
    end
  end

  # Registry of dummy opponent types
  DUMMY_OPPONENTS = {
    stationary: StationaryBot,
    spinner: SpinnerBot,
    chaser: ChaserBot,
    random: RandomBot,
    shielder: ShielderBot
  }.freeze

  module TestHarness
    # Run a test battle with your rubot against dummy opponents
    #
    # @param rubot_class [Class] Your rubot class to test
    # @param opponents [Array<Symbol>] Dummy opponent types (default: [:stationary])
    # @param count [Integer] Number of each opponent type (default: 1)
    # @param chronon_limit [Integer] Max chronons (default: 500)
    # @param debug [Boolean] Enable debug output (default: false)
    # @param watch [Boolean] Show terminal visualization (default: false)
    # @param seed [Integer, nil] Random seed for reproducibility
    # @param position [Hash, nil] Starting position for test rubot {x:, y:}
    #
    # @return [Hash] Battle results with winner, stats, seed, and events
    #
    # @example Basic test
    #   Rubowar.test_battle(MyBot)
    #
    # @example Test against multiple opponents
    #   Rubowar.test_battle(MyBot, opponents: [:spinner, :chaser])
    #
    # @example Watch the battle live
    #   Rubowar.test_battle(MyBot, opponents: [:chaser], watch: true)
    #
    # @example Reproducible test
    #   result = Rubowar.test_battle(MyBot, seed: 12345)
    #   puts "Seed used: #{result[:seed]}"  # Can replay with same seed
    #
    # @example Controlled starting position
    #   Rubowar.test_battle(MyBot, position: {x: 100, y: 100})
    #
    def self.run(rubot_class, opponents: [:stationary], count: 1, chronon_limit: 500,
                 debug: false, watch: false, seed: nil, position: nil)
      # Build list of rubot classes
      rubot_classes = [rubot_class]
      opponents.each do |opponent_type|
        opponent_class = DUMMY_OPPONENTS[opponent_type]
        raise ArgumentError, "Unknown opponent type: #{opponent_type}. Valid: #{DUMMY_OPPONENTS.keys.join(", ")}" unless opponent_class

        count.times { rubot_classes << opponent_class }
      end

      # Create battle with seed
      battle = Battle.local([], chronon_limit:, seed:)

      # Register test rubot with optional position
      test_actor = LocalActor.new(rubot_class)
      battle.register(test_actor, position:)

      # Register opponents
      rubot_classes[1..].each do |klass|
        battle.register(LocalActor.new(klass))
      end

      # Enable debug mode on the test rubot if requested
      # (set on the actor before spawning, will be available when rubot instance is created)
      test_actor.instance_variable_set(:@_debug_mode, true) if debug

      # Set up terminal renderer if watching
      if watch
        terminal = Renderers::Terminal.new(battle)
        battle.on(:chronon) do |tick_state|
          terminal.render(tick_state)
          sleep 0.05
        end
      end

      # Collect debug events if in debug mode
      debug_log = []
      if debug
        battle.on(:action_failed) do |data|
          debug_log << "[DEBUG] Action failed: #{data[:action]} - #{data[:reason]} (actor: #{data[:actor_id]})"
        end
      end

      # Run the battle
      battle.run

      # Show final state if watching
      if watch
        terminal = Renderers::Terminal.new(battle) unless terminal
        terminal.render_final(battle.winner)
      end

      # Print debug log
      debug_log.each { |msg| warn msg } if debug

      # Build results
      test_rubot = battle.arena.actors.first
      {
        winner: battle.winner&.name,
        won: battle.winner == test_rubot,
        chronons: battle.chronon,
        seed: battle.seed,  # For replay with same seed
        test_rubot: {
          name: test_rubot.name,
          health: test_rubot.health.round(1),
          damage_dealt: test_rubot.damage_dealt.round(1),
          damage_taken: test_rubot.damage_taken.round(1),
          alive: test_rubot.alive?
        },
        opponents: battle.arena.actors[1..].map do |actor|
          {
            name: actor.name,
            health: actor.health.round(1),
            damage_dealt: actor.damage_dealt.round(1),
            damage_taken: actor.damage_taken.round(1),
            alive: actor.alive?
          }
        end,
        debug_log:
      }
    end
  end

  # Convenience method at module level
  def self.test_battle(rubot_class, **options)
    TestHarness.run(rubot_class, **options)
  end
end
