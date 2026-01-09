# frozen_string_literal: true

# [file]
# purpose = "ASCII terminal renderer for watching battles in real-time"
# responsibility = "Convert battle state to visual grid representation"
# pattern = "Renderer / View"
#
# [class.Terminal]
# purpose = "Renders battle state as ASCII art in the terminal"
# input = "Battle instance and tick_state from chronon events"
# output = "ASCII grid with rubot positions, bullets, and status"
#
# [rendering]
# scale = "Arena coordinates divided by SCALE factor (default 10)"
# grid = "2D array of characters representing arena"
# y_axis = "Inverted (0 at bottom, height at top) for natural display"

module Rubowar
  module Renderers
    class Terminal
      # Display configuration
      SCALE = 10
      RUBOT_CHARS = %w[A B C D E F G H].freeze
      DEAD_CHAR = "X"
      BULLET_CHAR = "•"
      ENERGON_CHAR = "★"
      EMPTY_CHAR = "·"

      # Status display formatting
      STATUS_WIDTH = 3

      def initialize(battle)
        @battle = battle
        @arena = battle.arena
        @grid_width = @arena.width / SCALE
        @grid_height = @arena.height / SCALE
      end

      def render(tick_state)
        clear_screen
        grid = build_empty_grid
        place_energons(grid)
        place_bullets(grid: grid, bullets: tick_state[:bullets])
        place_rubots(grid: grid, actors: tick_state[:actors])
        print_grid(grid)
        print_status(tick_state)
      end

      def render_final(winner)
        puts
        print_separator
        if winner
          puts "🏆 WINNER: #{winner.rubot_class.name}"
          puts "   Health: #{winner.health}/#{winner.to_state.health}"
          puts "   Damage dealt: #{winner.damage_dealt}"
          puts "   Damage taken: #{winner.damage_taken}"
        else
          puts "⚔️  DRAW - No winner"
        end
        print_separator
      end

      private

      def clear_screen
        print "\e[2J\e[H"
      end

      def build_empty_grid
        Array.new(@grid_height) { Array.new(@grid_width) { EMPTY_CHAR } }
      end

      def place_energons(grid)
        @arena.energons.each do |energon|
          gx, gy = world_to_grid(world_x: energon.x, world_y: energon.y)
          grid[gy][gx] = ENERGON_CHAR
        end
      end

      def place_bullets(grid:, bullets:)
        bullets.each do |bullet|
          gx, gy = world_to_grid(world_x: bullet[:x], world_y: bullet[:y])
          grid[gy][gx] = BULLET_CHAR
        end
      end

      def place_rubots(grid:, actors:)
        actors.each_with_index do |rubot, index|
          gx, gy = world_to_grid(world_x: rubot.x, world_y: rubot.y)
          char = rubot.health.positive? ? RUBOT_CHARS[index] : DEAD_CHAR
          grid[gy][gx] = char
        end
      end

      def world_to_grid(world_x:, world_y:)
        gx = (world_x / SCALE).to_i.clamp(0, @grid_width - 1)
        # Invert Y axis: world Y=0 is bottom, grid row 0 is top
        gy = (@grid_height - 1 - (world_y / SCALE).to_i).clamp(0, @grid_height - 1)
        [gx, gy]
      end

      def print_grid(grid)
        border = "+#{"-" * @grid_width}+"
        puts border
        grid.each { |row| puts "|#{row.join}|" }
        puts border
      end

      def print_status(tick_state)
        puts "Chronon: #{tick_state[:chronons]}"
        puts

        tick_state[:actors].each_with_index do |rubot, index|
          print_rubot_status(rubot: rubot, index: index)
        end
      end

      def print_rubot_status(rubot:, index:)
        char = RUBOT_CHARS[index]
        status = rubot.health.positive? ? "ALIVE" : "DEAD "

        hp = format_stat(rubot.health)
        energy = format_stat(rubot.energy)
        shield = format_stat(rubot.shield_level, width: 2)

        puts "#{char}: HP=#{hp} E=#{energy} S=#{shield} [#{status}]"
      end

      def format_stat(value, width: STATUS_WIDTH)
        value.to_i.to_s.rjust(width)
      end

      def print_separator
        puts "-" * 40
      end
    end
  end
end
