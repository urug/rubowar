# Renderers

Rubowar uses a renderer system to visualize and record battles. Renderers subscribe to battle events and output game state in various formats.

## Architecture

Renderers follow an event-driven pattern:

1. **Subscribe** to `EventBus` events (`:chronon`, `:battle_end`)
2. **Receive** tick state data each chronon
3. **Output** formatted representation (terminal, JSON, HTML)

```
┌─────────┐     Events      ┌──────────┐
│  Battle │ ───────────────>│ EventBus │
└─────────┘                 └──────────┘
                                 │
           ┌─────────────────────┼─────────────────────┐
           │                     │                     │
           ▼                     ▼                     ▼
    ┌──────────┐          ┌───────────┐        ┌────────────┐
    │ Terminal │          │ JsonLogger│        │ HtmlCanvas │
    └──────────┘          └───────────┘        └────────────┘
         │                      │                    │
         ▼                      ▼                    ▼
    ANSI output             JSON file           HTML file
```

## Built-in Renderers

### Terminal

Real-time Unicode visualization in the terminal with ANSI colors.

```ruby
terminal = Rubowar::Renderers::Terminal.new(battle)

battle.on(:chronon) do |tick_state|
  terminal.render(tick_state)
  sleep 0.03  # ~30 FPS
end

battle.on(:battle_end) do |data|
  terminal.render_final(data[:winner])
end
```

**Features:**
- Unicode symbols for rubots (size-based: `●◉⬤`)
- Health-based coloring (green → yellow → red)
- Turret direction arrows (`→↗↑↖←↙↓↘`)
- Status display with HP, energy, shields
- Automatic screen clearing

### JsonLogger

Structured JSON output for replay, analysis, or ML training.

```ruby
# Stream mode: write NDJSON to file in real-time
File.open("battle.ndjson", "w") do |file|
  logger = Rubowar::Renderers::JsonLogger.new(battle, output: file)
  battle.on(:chronon) { |data| logger.render(data) }
  battle.on(:battle_end) { |data| logger.render_final(data[:winner]) }
  battle.run
end

# Collect mode: gather frames in memory
logger = Rubowar::Renderers::JsonLogger.new(battle)
battle.on(:chronon) { |data| logger.render(data) }
battle.on(:battle_end) { |data| logger.render_final(data[:winner]) }
battle.run

# Access complete battle data
puts logger.to_json
```

**Output Format:**

```json
{
  "metadata": {
    "arena": { "width": 640, "height": 480, "friction": 0.92 },
    "rubots": [
      { "name": "Spinner", "size": "medium", "id": "rbot-a1b2c3d4" }
    ],
    "recorded_at": "2024-01-15T10:30:00Z"
  },
  "frames": [
    {
      "type": "tick",
      "chronon": 1,
      "rubots": [
        {
          "id": "rbot-a1b2c3d4",
          "name": "Spinner",
          "x": 320.0, "y": 240.0,
          "velocity_x": 0.0, "velocity_y": 0.0,
          "speed": 0.0, "turret_angle": 45.0,
          "health": 100, "energy": 100,
          "shield_level": 0,
          "damage_dealt": 0, "damage_taken": 0,
          "size": "medium", "alive": true
        }
      ],
      "bullets": [],
      "energons": []
    },
    {
      "type": "summary",
      "winner": { "id": "rbot-a1b2c3d4", "name": "Spinner", ... },
      "outcome": "victory",
      "duration_ms": 1234
    }
  ]
}
```

### HtmlCanvas

Self-contained HTML files with animated Canvas visualization.

```ruby
html = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "replays")

battle.on(:chronon) { |data| html.render(data) }
battle.on(:battle_end) { |data| html.render_final(data[:winner]) }

battle.run

puts "Replay saved: #{html.filepath}"
# => replays/battle-20240115-103000-spinner-vs-tracker.html
```

**Features:**
- Play/pause, speed control (0.25x to 8x)
- Frame-by-frame stepping
- Timeline scrubber
- Keyboard shortcuts (Space, arrows, Home, End)
- Interpolated animation between frames
- Shield and health bar visualization
- No external dependencies (self-contained HTML)

## Creating Custom Renderers

Implement two methods: `render(tick_state)` and `render_final(winner)`.

### Minimal Example

```ruby
class MyRenderer
  def initialize(battle)
    @battle = battle
    @arena = battle.arena
  end

  # Called each chronon with game state
  def render(tick_state)
    puts "Chronon #{tick_state[:chronon]}: #{tick_state[:actors].count} rubots alive"
  end

  # Called when battle ends
  def render_final(winner)
    if winner
      puts "Winner: #{winner.rubot_class.name}"
    else
      puts "Draw!"
    end
  end
end
```

### Tick State Structure

The `tick_state` hash passed to `render()` contains:

```ruby
{
  chronon: Integer,           # Current chronon number
  actors: [RubotState, ...],  # Array of rubot state objects
  bullets: [
    { id:, x:, y:, velocity_x:, velocity_y: },
    ...
  ],
  energons: [Energon, ...]    # Active energon pickups
}
```

### RubotState Fields

Each actor in `tick_state[:actors]` is a `RubotState` with:

| Field | Type | Description |
|-------|------|-------------|
| `x`, `y` | Float | Position in arena |
| `velocity_x`, `velocity_y` | Float | Current velocity |
| `speed` | Float | Magnitude of velocity |
| `turret_angle` | Float | Turret direction (0-360°) |
| `health` | Integer | Current health |
| `energy` | Integer | Current energy |
| `shield_level` | Integer | Active shield amount |
| `damage_dealt` | Integer | Total damage dealt |
| `damage_taken` | Integer | Total damage received |
| `size` | Symbol | `:small`, `:medium`, or `:large` |

### Winner Object

The `winner` passed to `render_final()` is a `LocalActor` (or nil for draws) with:

```ruby
winner.id                # "rbot-a1b2c3d4"
winner.rubot_class.name  # "Spinner"
winner.x, winner.y       # Final position
winner.health            # Remaining health
winner.damage_dealt      # Total damage dealt
winner.damage_taken      # Total damage received
winner.size              # :small, :medium, :large
winner.max_health        # Size-based max HP
```

### Subscribing to Events

Renderers subscribe to events via the battle's event bus:

```ruby
renderer = MyRenderer.new(battle)

# Main game tick - fires every chronon
battle.on(:chronon) { |data| renderer.render(data) }

# Battle conclusion
battle.on(:battle_end) { |data| renderer.render_final(data[:winner]) }

# Optional: subscribe to specific events
battle.on(:fire) { |data| puts "Fire! #{data}" }
battle.on(:hit) { |data| puts "Hit! #{data}" }
battle.on(:death) { |data| puts "Death! #{data}" }
```

### Available Events

| Event | Fields | Description |
|-------|--------|-------------|
| `:chronon` | `chronon`, `actors`, `bullets`, `energons` | Each game tick |
| `:battle_end` | `winner`, `outcome` | Battle concluded |
| `:fire` | `actor_id`, `bullet_id`, `x`, `y`, `angle`, `damage` | Rubot fires |
| `:hit` | `attacker_id`, `target_id`, `bullet_id`, `x`, `y`, `damage` | Bullet hit |
| `:shield` | `actor_id`, `energy` | Shield raised |
| `:collision` | `actor_a_id`, `actor_b_id`, `damage_to_a`, `damage_to_b` | Rubot collision |
| `:wall_hit` | `actor_id`, `damage`, `walls` | Wall collision |
| `:death` | `actor_id` | Rubot died |
| `:error` | `actor_id`, `error` | Rubot code crashed |
| `:action_failed` | `actor_id`, `action`, `reason` | Action couldn't execute |
| `:energon_spawn` | `energon_id`, `x`, `y` | Energon appeared |
| `:energon_spawn_failed` | (none) | No valid spawn position |
| `:energon_collect` | `actor_id`, `energon_id`, `x`, `y`, `amount` | Energon collected |

All events include a `chronon` field with the current chronon number.

### Complete Custom Renderer Example

```ruby
module Rubowar
  module Renderers
    class CsvLogger
      def initialize(battle, output:)
        @battle = battle
        @output = output
        @output.puts "chronon,rubot,x,y,health,energy,shield"
      end

      def render(tick_state)
        tick_state[:actors].each do |state|
          actor = @battle.arena.actors.find { |a| a.to_state == state }
          @output.puts [
            tick_state[:chronon],
            actor.rubot_class.name,
            state.x.round(2),
            state.y.round(2),
            state.health,
            state.energy,
            state.shield_level
          ].join(",")
        end
      end

      def render_final(winner)
        @output.puts "# Winner: #{winner&.rubot_class&.name || 'Draw'}"
        @output.close
      end
    end
  end
end

# Usage
File.open("battle.csv", "w") do |file|
  csv = Rubowar::Renderers::CsvLogger.new(battle, output: file)
  battle.on(:chronon) { |data| csv.render(data) }
  battle.on(:battle_end) { |data| csv.render_final(data[:winner]) }
  battle.run
end
```

## Using Multiple Renderers

Multiple renderers can run simultaneously:

```ruby
battle = Rubowar::Battle.new(arena:, event_bus:)

# Terminal for live viewing
terminal = Rubowar::Renderers::Terminal.new(battle)
battle.on(:chronon) do |data|
  terminal.render(data)
  sleep 0.03
end

# JSON for data analysis
json = Rubowar::Renderers::JsonLogger.new(battle)
battle.on(:chronon) { |data| json.render(data) }
battle.on(:battle_end) { |data| json.render_final(data[:winner]) }

# HTML for shareable replay
html = Rubowar::Renderers::HtmlCanvas.new(battle, output_dir: "replays")
battle.on(:chronon) { |data| html.render(data) }
battle.on(:battle_end) { |data| html.render_final(data[:winner]) }

battle.run

terminal.render_final(battle.winner)
puts json.to_json
puts "Replay: #{html.filepath}"
```

## Command-Line Usage

The `bin/battle` script supports renderer options:

```bash
# Terminal visualization
bin/battle Spinner Tracker --watch

# HTML replay output
bin/battle Spinner Tracker --html replays/

# JSON log output
bin/battle Spinner Tracker --json-log battle.json

# All renderers together
bin/battle Spinner Tracker --watch --html replays/ --json-log battle.json
```

The `bin/log` script is specialized for JSON output:

```bash
# Stream NDJSON to stdout
bin/log Spinner Tracker --stream

# Stream NDJSON to file
bin/log Spinner Tracker --stream --output battle.ndjson

# Collect and output complete JSON
bin/log Spinner Tracker --pretty
```
