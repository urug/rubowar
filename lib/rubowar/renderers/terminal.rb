# frozen_string_literal: true

# [file]
# purpose = "Unicode terminal renderer for watching battles in real-time"
# responsibility = "Convert battle state to visual grid representation"
# pattern = "Renderer / View"
#
# [class.Terminal]
# purpose = "Renders battle state with Unicode graphics and ANSI colors"
# input = "Battle instance and tick_state from chronon events"
# output = "Unicode grid with rubot positions, bullets, and status"
#
# [rendering]
# scale = "Arena coordinates divided by SCALE factor (default 10)"
# grid = "2D array of characters representing arena"
# y_axis = "Inverted (0 at bottom, height at top) for natural display"
# colors = "ANSI escape codes for health-based coloring"

module Rubowar
  module Renderers
    class Terminal
      # Display configuration
      SCALE = 10
      ASPECT_RATIO = 2.0 # Terminal chars are ~2x taller than wide

      # Size-based rubot symbols (up to 8 rubots per size)
      RUBOT_CHARS = {
        small: %w[● ○ ◐ ◑ ◒ ◓ ◔ ◕],
        medium: %w[◉ ◎ ⊙ ⊚ ⦿ ⊛ ⊜ ⊝],
        large: %w[⬤ ◯ ⬢ ⬡ ⏣ ⎔ ⏢ ⏥]
      }.freeze

      DEAD_CHAR = "☠"
      BULLET_CHAR = "∙"
      ENERGON_CHAR = "◆"
      EMPTY_CHAR = " "

      # Turret direction arrows (8 directions, starting at East/0°)
      TURRET_ARROWS = %w[→ ↗ ↑ ↖ ← ↙ ↓ ↘].freeze

      # ANSI color codes
      COLORS = {
        red: "\e[31m",
        yellow: "\e[33m",
        green: "\e[32m",
        blue: "\e[34m",
        cyan: "\e[36m",
        reset: "\e[0m"
      }.freeze

      # Status display formatting
      STATUS_WIDTH = 3

      def initialize(battle)
        @battle = battle
        @arena = battle.arena
        @grid_width = @arena.width / SCALE
        @grid_height = (@arena.height / SCALE / ASPECT_RATIO).to_i
      end

      def render(tick_state)
        clear_screen
        grid = build_empty_grid
        place_energons(grid)
        place_bullets(grid:, bullets: tick_state[:bullets])
        place_rubots(grid:, actors: tick_state[:actors])
        print_grid(grid)
        print_status(tick_state)
      end

      def render_final(winner)
        puts
        print_separator
        if winner
          puts "🏆 WINNER: #{winner.rubot_class.name}"
          puts "   Health: #{winner.health}/#{winner.max_health}"
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
          char = rubot_char(rubot:, index:)
          grid[gy][gx] = colorize_by_health(char, rubot:)
        end
      end

      def rubot_char(rubot:, index:)
        return DEAD_CHAR unless rubot.health.positive?

        size_chars = RUBOT_CHARS[rubot.size] || RUBOT_CHARS[:medium]
        size_chars[index % size_chars.length]
      end

      def colorize_by_health(char, rubot:)
        return char unless rubot.health.positive?

        max_health = Config::Rubot::SIZES[rubot.size][:max_health]
        ratio = rubot.health.to_f / max_health
        color = case ratio
                when 0.6.. then COLORS[:green]
                when 0.3.. then COLORS[:yellow]
                else COLORS[:red]
                end
        "#{color}#{char}#{COLORS[:reset]}"
      end

      def turret_arrow(angle)
        index = ((angle + 22.5) / 45).floor % 8
        TURRET_ARROWS[index]
      end

      def world_to_grid(world_x:, world_y:)
        gx = (world_x / SCALE).to_i.clamp(0, @grid_width - 1)
        # Invert Y axis: world Y=0 is bottom, grid row 0 is top
        # Apply aspect ratio to Y for proper proportions
        gy = (@grid_height - 1 - (world_y / SCALE / ASPECT_RATIO).to_i).clamp(0, @grid_height - 1)
        [gx, gy]
      end

      def print_grid(grid)
        puts "┌#{"─" * @grid_width}┐"
        grid.each { |row| puts "│#{row.join}│" }
        puts "└#{"─" * @grid_width}┘"
      end

      def print_status(tick_state)
        puts "Chronon: #{tick_state[:chronon]}"
        puts

        tick_state[:actors].each_with_index do |rubot, index|
          print_rubot_status(rubot:, index:)
        end
      end

      def print_rubot_status(rubot:, index:)
        char = rubot_char(rubot:, index:)
        colored_char = colorize_by_health(char, rubot:)
        arrow = turret_arrow(rubot.turret_angle)

        hp = format_stat(rubot.health)
        energy = format_stat(rubot.energy)
        shield = format_stat(rubot.shield_level, width: 2)

        if rubot.health.positive?
          puts "#{colored_char}#{arrow} HP=#{hp} E=#{energy} S=#{shield}"
        else
          puts "#{colored_char}  HP=#{hp} E=#{energy} S=#{shield} [DEAD]"
        end
      end

      def format_stat(value, width: STATUS_WIDTH)
        value.to_i.to_s.rjust(width)
      end

      def print_separator
        puts "─" * 40
      end
    end
  end
end
