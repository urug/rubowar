# frozen_string_literal: true

# [file]
# purpose = "Battle statistics for post-battle analysis"
# responsibility = "Provide convenient access to battle and per-bot statistics"
# pattern = "Value Object with Hash-like access"
#
# [class.BattleStats]
# purpose = "Statistics container supporting battle.stats and battle.stats[bot_id]"
# usage = """
#   result = battle.stats
#   puts result.chronons          # Overall: number of chronons
#   puts result.winner            # Overall: winner name or nil
#   puts result[bot.id][:damage_dealt]  # Per-bot stat
# """

module Rubowar
  class BattleStats
    attr_reader :battle

    def initialize(battle)
      @battle = battle
      @bot_stats = build_bot_stats
    end

    # Access per-bot statistics by actor ID
    # @param bot_id [String] The actor's ID
    # @return [Hash, nil] Bot statistics or nil if not found
    #
    # @example
    #   stats[bot.id][:damage_dealt]  # => 150.5
    #   stats[bot.id][:alive]         # => true
    #
    def [](bot_id)
      @bot_stats[bot_id]
    end

    # List all bot IDs
    # @return [Array<String>] All actor IDs in the battle
    def bot_ids
      @bot_stats.keys
    end

    # Iterate over all bot stats
    # @yield [id, stats] Each bot's ID and stats hash
    def each(&)
      @bot_stats.each(&)
    end

    # Number of chronons the battle ran
    # @return [Integer]
    def chronons
      @battle.chronon
    end

    # The random seed used for this battle
    # @return [Integer]
    def seed
      @battle.seed
    end

    # Winner's name, or nil for a draw
    # @return [String, nil]
    def winner
      @battle.winner&.name
    end

    # Winner's ID, or nil for a draw
    # @return [String, nil]
    def winner_id
      @battle.winner&.id
    end

    # Battle outcome
    # @return [Symbol] :victory or :draw
    def outcome
      @battle.winner ? :victory : :draw
    end

    # Total damage dealt across all bots
    # @return [Float]
    def total_damage
      @bot_stats.values.sum { |s| s[:damage_dealt] }
    end

    # Number of bots still alive
    # @return [Integer]
    def alive_count
      @bot_stats.values.count { |s| s[:alive] }
    end

    # Number of bots that died
    # @return [Integer]
    def death_count
      @bot_stats.values.count { |s| !s[:alive] }
    end

    # Convert to hash for serialization
    # @return [Hash] Full statistics as a hash
    def to_h
      {
        chronons:,
        seed:,
        winner:,
        winner_id:,
        outcome:,
        total_damage: total_damage.round(1),
        alive_count:,
        death_count:,
        bots: @bot_stats
      }
    end

    # Pretty print stats
    def to_s
      lines = []
      lines << "Battle Stats (#{chronons} chronons, seed: #{seed})"
      lines << "  Outcome: #{outcome} - Winner: #{winner || 'none (draw)'}"
      lines << "  Total damage: #{total_damage.round(1)}"
      lines << ""
      lines << "  Bots:"
      @bot_stats.each do |id, stats|
        status = stats[:alive] ? "alive" : "dead"
        lines << "    #{stats[:name]} (#{id[0..7]}...): #{status}"
        lines << "      HP: #{stats[:health].round(1)}/#{stats[:max_health]} | Energy: #{stats[:energy].round(1)}"
        lines << "      Damage dealt: #{stats[:damage_dealt].round(1)} | Damage taken: #{stats[:damage_taken].round(1)}"
      end
      lines.join("\n")
    end

    private

    def build_bot_stats
      @battle.arena.actors.to_h do |actor|
        [
          actor.id,
          {
            id: actor.id,
            name: actor.name,
            health: actor.health,
            max_health: actor.max_health,
            energy: actor.energy,
            damage_dealt: actor.damage_dealt,
            damage_taken: actor.damage_taken,
            alive: actor.alive?,
            x: actor.x,
            y: actor.y,
            turret_angle: actor.turret_angle
          }
        ]
      end
    end
  end
end
