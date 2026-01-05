# Rubowar

A competitive programming game where Ruby club members write Ruby classes to control robots ("Rubots") that battle in an arena. The engine is a standalone Ruby gem with a pluggable renderer interface.

## Quick Start

```ruby
class MyRobot
  include Rubot
  size :medium  # :small, :medium, or :large

  def tick
    turret(10)              # Rotate turret
    fire(5) if look(1)      # Fire when we see someone
    thrust(2) if speed < 5  # Keep moving
  end
end
```

## Robot API

### State Accessors (read-only)

| Method | Description |
|--------|-------------|
| `x`, `y` | Position in arena |
| `velocity_x`, `velocity_y` | Current velocity |
| `speed` | Velocity magnitude |
| `body_angle` | Body direction (0-360) |
| `turret_angle` | Turret direction (0-360, absolute) |
| `health` | Current HP (starts 100) |
| `energy` | Current energy (max 100) |
| `shield_level` | Shield strength (0-50, degrades 2/tick) |
| `arena_width`, `arena_height` | Arena dimensions |
| `friction` | Arena friction (default 0.95) |
| `tick_number` | Current game tick |
| `damage_dealt`, `damage_taken` | Match stats |
| `energons` | All energon positions (free) |
| `size` | Robot size (:small, :medium, :large) |

### Actions

| Method | Cost | Effect |
|--------|------|--------|
| `thrust(energy)` | energy | velocity = sqrt(energy) * 1.5 |
| `turn(degrees)` | \|degrees\|/10 | Rotate body |
| `turret(degrees)` | \|degrees\|/30 | Rotate turret (cheaper) |
| `fire(energy)` | energy | Damage = 1.5 * energy, 18 u/tick |
| `shield(energy)` | energy | Add to shield (max 50) |

### Sensing

| Method | Cost | Returns |
|--------|------|---------|
| `look(1-5)` | 1-5 | Line scan, more energy = more detail |
| `scan(width)` | width | Cone scan, returns robots + bullets |
| `pulse(radius)` | radius^2/10 | Circle scan, position + size only |

**look(energy) detail levels:**
- 1: position + size
- 2: + velocity
- 3: + shield_level
- 4: + health
- 5: + energy

### Callbacks

```ruby
def on_hit(damage, direction)  # Projectile hit
def on_spawn                   # Match start
def on_death                   # Health reached 0
def on_wall                    # Wall collision (10 damage)
def on_collision(robot)        # Robot collision (5 damage)
def on_energon(amount)         # Collected energon
```

### Robot Sizes

| Size | Radius | Energy Regen | Collision Bonus |
|------|--------|--------------|-----------------|
| `:small` | 15 | +8/tick | Takes +3 from larger |
| `:medium` | 20 | +10/tick | Standard |
| `:large` | 25 | +12/tick | Deals +3 to smaller |

## Arena

- **Dimensions**: Variable (default 800x600)
- **Origin**: Bottom-left (0,0)
- **Angles**: 0 = East, 90 = North, 180 = West, 270 = South
- **Friction**: 0.95 default (configurable)
- **Max speed**: 20 u/tick
- **Wall collision**: 10 damage + bounce
- **Robot collision**: 5 damage (with size modifiers)

## Physics

- `thrust(energy)` adds velocity: sqrt(energy) * 1.5
- Bullets travel 18 u/tick
- Self-damage is possible (your bullets can hit you)
- Friction slows robots each tick (velocity *= friction)

## Renderer Interface

The engine emits events for any renderer:

```ruby
match = Rubowar::Match.new(robots: [Spinner, Tracker])

# Block-based (real-time)
match.on(:tick) { |state| render_frame(state) }
match.on(:hit) { |event| play_sound(:hit) }
match.run

# Collect events (replays)
events = match.run
save_replay(events)

# Built-in terminal
match.run(renderer: Rubowar::Renderers::Terminal)
```

**Event types**: `:tick`, `:fire`, `:hit`, `:death`, `:wall_collision`, `:robot_collision`, `:energon_spawn`, `:energon_collect`, `:match_end`

## Victory

- Last robot standing wins
- Tick limit (5000) prevents stalemates
- Tiebreaker: highest HP, then most damage dealt

## Error Handling

If robot code crashes or times out: **10 damage** + skip tick.

## Project Structure

```
rubowar/
├── lib/
│   ├── rubowar/
│   │   ├── rubot.rb           # Module participants include
│   │   ├── arena.rb           # Physics, collisions
│   │   ├── match.rb           # Game loop
│   │   ├── robot_runner.rb    # Sandboxed execution
│   │   ├── bullet.rb          # Projectile tracking
│   │   ├── energon.rb         # Energy power-up
│   │   └── events.rb          # Event types
│   └── rubowar.rb
├── test/
├── robots/                    # Example robots
├── bin/rubowar                # CLI
└── rubowar.gemspec
```

## License

MIT License - see [LICENSE](LICENSE)
