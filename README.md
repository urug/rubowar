# Rubowar

A competitive programming game where Ruby club members write Ruby classes to control robots ("Rubots") that battle in an arena. The engine is a standalone Ruby gem with a pluggable renderer interface.

## Quick Start

```ruby
class MyRubot
  include Rubowar::Rubot
  size :medium  # :small, :medium, or :large

  def on_spawn
    @heading = rand(360)
  end

  def tick
    turret(10)                              # Rotate turret
    fire(5) if look                         # Fire when we see someone
    thrust(speed: 3, angle: @heading)       # Move in heading direction
  end
end
```

## Rubot API

### State Accessors (read-only)

| Method | Description |
|--------|-------------|
| `x`, `y` | Position in arena |
| `velocity_x`, `velocity_y` | Current velocity |
| `speed` | Velocity magnitude |
| `turret_angle` | Turret direction (0-360, world coordinates) |
| `health` | Current HP (varies by size) |
| `energy` | Current energy (max 100) |
| `shield_level` | Shield strength (0-50, degrades 2/tick) |
| `arena_width`, `arena_height` | Arena dimensions |
| `friction` | Arena friction (default 0.95) |
| `tick_number` | Current game tick |
| `damage_dealt`, `damage_taken` | Match stats |
| `energons` | All energon positions (free) |
| `size` | Rubot size (:small, :medium, :large) |

### Actions

| Method | Cost | Effect |
|--------|------|--------|
| `thrust(speed:, angle:)` | (speed/1.5)^2 x mass x direction | Add velocity in world direction |
| `turret(degrees)` | \|degrees\|/30 | Rotate turret |
| `fire(energy)` | energy | Damage = 1.5 x energy, bullet speed 18 |
| `shield(energy)` | energy | Add to shield (max 50) |

**Thrust mechanics:**
- `angle` is in world coordinates (0 = east, 90 = north)
- Cost increases with mass (larger rubots cost more to move)
- Changing direction costs more (1.0x same direction, 2.0x opposite)
- If you can't afford full thrust, you get partial thrust and energy drains to zero

### Sensing

| Method | Cost | Returns |
|--------|------|---------|
| `look(*attributes)` | 1 + attribute costs | Line scan in turret direction |

**look() attributes and costs:**
- Base (x, y): 1 energy
- `:size`: +1 energy
- `:velocity`: +2 energy (adds velocity_x, velocity_y)
- `:shield`: +2 energy (adds shield_level)
- `:health`: +3 energy
- `:energy`: +3 energy

```ruby
look                    # 1 energy  -> { x:, y: } or nil
look(:size)             # 2 energy  -> { x:, y:, size: }
look(:size, :velocity)  # 4 energy  -> { x:, y:, size:, velocity_x:, velocity_y: }
look(:size, :velocity, :shield, :health, :energy)  # 12 energy -> everything
```

**Note:** `look()` returns the result from the PREVIOUS tick's look. The current look result won't be available until the next tick.

### Callbacks

```ruby
def on_hit(damage, direction)  # Projectile hit
def on_spawn                   # Match start
def on_death                   # Health reached 0
def on_wall                    # Wall collision
def on_collision(other_rubot)  # Rubot collision
def on_energon(amount)         # Collected energon
```

### Rubot Sizes

| Size | Radius | HP | Energy Regen | Mass |
|------|--------|-----|--------------|------|
| `:small` | 15 | 80 | +8/tick | 0.56 |
| `:medium` | 20 | 100 | +10/tick | 1.0 |
| `:large` | 25 | 120 | +12/tick | 1.56 |

**Tradeoffs:**
- **Small**: Harder to hit, cheapest thrust, but least HP
- **Medium**: Balanced baseline
- **Large**: Most HP and firepower, but expensive to move and easier to hit

## Arena

- **Dimensions**: Variable (default 800x600)
- **Origin**: Bottom-left (0,0)
- **Angles**: 0 = East, 90 = North, 180 = West, 270 = South
- **Friction**: 0.95 default (velocity *= friction each tick)
- **Max speed**: 20 u/tick

## Physics

### Movement
- `thrust(speed:, angle:)` adds velocity in the specified world direction
- Cost: `(speed/1.5)^2 x mass x direction_multiplier`
- Direction multiplier: 1.0 (same direction) to 2.0 (opposite direction)
- Friction slows rubots each tick (velocity *= 0.95)

### Bullets
- Travel 18 u/tick (slightly slower than max rubot speed of 20)
- Spawn at edge of rubot (position + rubot radius + bullet radius)
- Self-damage is possible (your bullets can hit you if you're fast enough)

### Collision Damage
- **Wall**: `2 + speed x 0.75` (at max speed: 17 damage)
- **Rubot**: `2 + attacker_mass x attacker_speed x 0.5` (momentum-based)

Large rubots deal more collision damage due to higher mass.

## Renderer Interface

The engine emits events for any renderer:

```ruby
battle = Rubowar::Battle.new(rubots: [Spinner, Tracker])

# Block-based (real-time)
battle.on(:tick) { |state| render_frame(state) }
battle.on(:hit) { |event| play_sound(:hit) }
battle.run

# Collect events (replays)
events = battle.run
save_replay(events)

# Built-in terminal
battle.run(renderer: Rubowar::Renderers::Terminal)
```

**Event types**: `:tick`, `:fire`, `:hit`, `:death`, `:wall_collision`, `:rubot_collision`, `:energon_spawn`, `:energon_collect`, `:battle_end`

## Victory

- Last rubot standing wins
- Tick limit (5000) prevents stalemates
- Tiebreaker: highest HP, then most damage dealt

## Error Handling

If rubot code crashes or times out: **10 damage** + skip tick.

## Project Structure

```
rubowar/
├── lib/
│   ├── rubowar/
│   │   ├── rubot.rb           # Module participants include
│   │   ├── arena.rb           # Physics, collisions
│   │   ├── battle.rb          # Game loop
│   │   ├── rubot_runner.rb    # Mutable state tracking
│   │   ├── rubot_state.rb     # Immutable state snapshots
│   │   ├── arena_state.rb     # Arena state snapshots
│   │   ├── bullet.rb          # Projectile tracking
│   │   └── renderers/
│   │       └── terminal.rb    # ASCII visualization
│   └── rubowar.rb
├── test/
├── robots/                    # Example rubots
├── bin/rubowar                # CLI
└── rubowar.gemspec
```

## License

MIT License - see [LICENSE](LICENSE)
