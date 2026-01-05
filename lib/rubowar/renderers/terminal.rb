# frozen_string_literal: true

module Rubowar
  module Renderers
    class Terminal
      SCALE = 10
      RUBOT_CHARS = %w[A B C D E F G H].freeze
      BULLET_CHAR = "•"
      EMPTY_CHAR = "."

      def initialize(battle)
        @battle = battle
        @width = battle.arena.width / SCALE
        @height = battle.arena.height / SCALE
      end

      def render(tick_state)
        clear_screen
        grid = build_grid(tick_state)
        print_grid(grid)
        print_status(tick_state)
      end

      def render_final(winner)
        puts
        if winner
          puts "WINNER: #{winner.rubot_class.name}"
          puts "  Health: #{winner.health}"
          puts "  Damage dealt: #{winner.damage_dealt}"
        else
          puts "DRAW - No winner"
        end
      end

      private

      def clear_screen
        print "\e[2J\e[H"
      end

      def build_grid(tick_state)
        grid = Array.new(@height) { Array.new(@width) { EMPTY_CHAR } }

        # Draw bullets
        tick_state[:bullets].each do |bullet|
          gx = (bullet[:x] / SCALE).to_i.clamp(0, @width - 1)
          gy = (@height - 1 - (bullet[:y] / SCALE).to_i).clamp(0, @height - 1)
          grid[gy][gx] = BULLET_CHAR
        end

        # Draw rubots
        tick_state[:runners].each_with_index do |rubot, index|
          gx = (rubot.x / SCALE).to_i.clamp(0, @width - 1)
          gy = (@height - 1 - (rubot.y / SCALE).to_i).clamp(0, @height - 1)
          char = rubot.health > 0 ? RUBOT_CHARS[index] : "X"
          grid[gy][gx] = char
        end

        grid
      end

      def print_grid(grid)
        border = "+" + "-" * @width + "+"
        puts border
        grid.each do |row|
          puts "|" + row.join + "|"
        end
        puts border
      end

      def print_status(tick_state)
        puts "Tick: #{tick_state[:tick_number]}"
        puts

        tick_state[:runners].each_with_index do |rubot, index|
          char = RUBOT_CHARS[index]
          status = rubot.health > 0 ? "ALIVE" : "DEAD"
          puts "#{char}: HP=#{rubot.health.to_i.to_s.rjust(3)} E=#{rubot.energy.to_i.to_s.rjust(3)} Shield=#{rubot.shield_level.to_i.to_s.rjust(2)} [#{status}]"
        end
      end
    end
  end
end
