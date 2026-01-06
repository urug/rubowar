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
    fire(5) if probe                        # Fire when we see someone
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
| `shield_level` | Shield strength (0 to max_health, decays 12%/tick) |
| `arena_width`, `arena_height` | Arena dimensions |
| `friction` | Arena friction (default 0.95) |
| `tick_number` | Current game tick |
| `damage_dealt`, `damage_taken` | Match stats |
| `energons` | All energon positions `[{x:, y:}]` (free) |
| `size` | Rubot size (:small, :medium, :large) |
| `live_rubot_count` | Number of rubots still alive |
| `energon_spawn_interval` | Ticks between energon spawns (default 80) |
| `energon_growth_rate` | Energy growth per tick (default 1.0) |

### Actions

| Method | Cost | Effect |
|--------|------|--------|
| `thrust(speed:, angle:)` | (speed/1.5)^2 x mass x direction | Add velocity in world direction |
| `turret(degrees)` | \|degrees\|/30 | Rotate turret |
| `fire(energy)` | energy | Damage = 1.5 x energy, bullet speed 18 |
| `shield(energy)` | energy | Add to shield (max = HP cap, decays 12%/tick) |

### Action Processing Order

**Actions are processed in phases, not in the order you call them.** This ensures fairness (no spawn-order advantage) and creates intuitive "move then shoot" behavior.

```
Phase 1: SENSE   → All probe(), scan(), pulse() for all rubots
Phase 2: MOVE    → All thrust(), turret() for all rubots → physics (movement, collisions)
Phase 3: COMBAT  → All fire(), shield() for all rubots → bullet physics
```

**Energy is deducted in phase order.** If you call `fire(10)` before `pulse(distance: 100)` in your code, the pulse still executes first and uses its energy first:

```ruby
def tick
  fire(10)                  # Queued, but processed LAST (combat phase)
  pulse(distance: 100)      # Queued second, but processed FIRST (sense phase)
  thrust(speed: 5, angle: 0) # Processed in middle (move phase)
end
```

With 15 energy available:
- Pulse runs first: costs ~4 energy, leaving 11
- Thrust runs second: costs ~11 energy, leaving 0
- Fire runs last: insufficient energy, fails silently

**Structure your code accordingly.** Check energy before expensive sensing operations, and don't assume fire() will "beat" a pulse() to the remaining energy.

**Bullets spawn from your post-movement position.** You move, then you shoot from where you are - not from where you were.

**Thrust mechanics:**
- `angle` is in world coordinates (0 = east, 90 = north)
- Cost increases with mass (larger rubots cost more to move)
- Changing direction costs more (1.0x same direction, 2.0x opposite)
- If you can't afford full thrust, you get partial thrust and energy drains to zero

### Sensing

| Method | Cost | Returns |
|--------|------|---------|
| `probe(*attributes)` | 1 + attribute costs | Line scan in turret direction |
| `scan(angle:, distance:, velocity:, owner:)` | 3 + area cost [+2] [+1] | Arc scan for all targets |
| `pulse(distance:, owner:)` | 2 + ceil(distance/75) [+1] | Omnidirectional radar ping |
| `detect` | 2 | Counter-intelligence: how many times you were sensed |

**probe() - Single target, detailed info:**
- Base: 1 energy (returns `:size` - detection ping)
- `:position`: +4 energy (x, y coordinates)
- `:velocity`: +3 energy (velocity_x, velocity_y)
- `:turret_angle`: +2 energy
- `:shield`: +2 energy (shield_level)
- `:health`: +3 energy
- `:energy`: +3 energy

```ruby
probe                    # 1 energy  -> { size: } or {} if no target
probe(:position)         # 5 energy  -> { size:, x:, y: }
probe(:position, :velocity)  # 8 energy  -> { size:, x:, y:, velocity_x:, velocity_y: }
```

**scan() - Multiple targets, position/velocity only:**
- Cost: `3 + ceil(angle/20) + ceil(distance/100)` [+2 for velocity] [+1 for owner]
- Returns array of all rubots and bullets in arc
- Each result: `{ x:, y:, type: :rubot/:bullet }`
- With velocity: adds `velocity_x:, velocity_y:`
- With owner: adds `owner:` (class name of rubot that fired bullet, nil for rubots)

```ruby
scan(angle: 20, distance: 100)                 # 5 energy  -> [{x:, y:, type:}, ...]
scan(angle: 20, distance: 100, velocity: true) # 7 energy  -> [{x:, y:, velocity_x:, velocity_y:, type:}, ...]
scan(angle: 20, distance: 100, owner: true)    # 6 energy  -> [{x:, y:, type:, owner:}, ...]
scan(angle: 90, distance: 300)                 # 11 energy -> wide arc scan
```

**pulse() - Quick 360° awareness ping:**
- Cost: `2 + ceil(distance/75)` [+1 for owner]
- Returns array of all rubots and bullets within radius
- Each result: `{ x:, y:, type: :rubot/:bullet }`
- With owner: adds `owner:` (class name of rubot that fired bullet, nil for rubots)

```ruby
pulse(distance: 75)               # 3 energy  -> [{x:, y:, type:}, ...]
pulse(distance: 100)              # 4 energy
pulse(distance: 100, owner: true) # 5 energy  -> [{x:, y:, type:, owner:}, ...]
```

**detect() - Counter-intelligence:**
- Cost: 2 energy
- Returns: `{ probed: N, scanned: N, pulsed: N }` - how many times you were sensed this tick
- Use to detect if enemies are tracking you

```ruby
detect                   # 2 energy  -> { probed: 1, scanned: 0, pulsed: 2 }
```

**Note:** All sensing methods (`probe()`, `scan()`, `pulse()`, `detect()`) return results from the PREVIOUS tick. Current results won't be available until the next tick.

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

### Wall Bounce
Wall collisions absorb most of your momentum. Larger rubots retain slightly more velocity:
- Bounce velocity = `velocity x mass x 0.12`
- **Small** (0.56 mass): 7% velocity retained
- **Medium** (1.0 mass): 12% velocity retained
- **Large** (1.56 mass): 19% velocity retained

Walls can't be used for free direction changes - you'll lose most of your speed.

## Energons

Energy power-ups that spawn periodically and grow in value over time.

### Mechanics
- **Spawn rate**: Every 80 ticks (configurable)
- **Starting value**: 1 energy
- **Growth**: +1 energy per tick alive
- **Collection**: Touch to collect (8 unit radius)
- **Spawn position**: Maximizes minimum distance from all bots, avoids walls (15% buffer)

### Detection
- `energons` accessor returns `[{x:, y:}]` - always visible, free
- Value is hidden until collected (older = more valuable)
- `energon_spawn_interval` and `energon_growth_rate` tell you the rules

### Strategy
- Early collection = small reward, less risk
- Late collection = big reward, more competition
- Spawns away from corners to discourage camping

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
│   │   ├── energon.rb         # Energy power-ups
│   │   ├── sensing_costs.rb   # Sensing cost calculations
│   │   └── renderers/
│   │       └── terminal.rb    # ASCII visualization
│   └── rubowar.rb
├── test/
├── robots/                    # Example rubots (spinner, coroner, crusher, hunter, patroller, avoider)
├── bin/rubowar                # CLI (not yet implemented)
└── rubowar.gemspec
```

## License

MIT License - see [LICENSE](LICENSE)
