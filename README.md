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

  def act
    rotate_turret(10)                       # Rotate turret
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
| `shield_level` | Shield strength (0 to max_health, decays 12%/chronon) |
| `arena_width`, `arena_height` | Arena dimensions |
| `friction` | Arena friction (default 0.92) |
| `chronons` | Current game tick |
| `damage_dealt`, `damage_taken` | Match stats |
| `energons` | All energon positions `[{x:, y:}]` (free) |
| `size` | Rubot size (:small, :medium, :large) |
| `live_rubot_count` | Number of rubots still alive |
| `energon_spawn_interval` | Ticks between energon spawns (default 50) |
| `energon_growth_rate` | Energy growth per chronon (default 1.0) |

### Actions

| Method | Cost | Effect |
|--------|------|--------|
| `thrust(speed:, angle:)` | (speed/1.5)^2 x mass x direction | Add velocity in world direction |
| `rotate_turret(degrees)` | ceil(\|degrees\|/24) | Rotate turret |
| `fire(energy)` | energy | Damage = 1.5 x energy, bullet speed 18 |
| `shield(energy)` | energy | Add to shield (max = HP cap, decays 12%/chronon) |

### Action Processing Order

**Actions are processed in phases, not in the order you call them.** This ensures fairness (no spawn-order advantage) and creates intuitive "move then shoot" behavior.

```
Phase 1: SENSE   → All probe(), scan(), pulse() for all rubots
Phase 2: MOVE    → All thrust(), rotate_turret() for all rubots → physics (movement, collisions)
Phase 3: COMBAT  → All fire(), shield() for all rubots → bullet physics
```

**Energy is deducted in phase order.** If you call `fire(10)` before `pulse(distance: 100)` in your code, the pulse still executes first and uses its energy first:

```ruby
def act
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
- Returns: `{ probed: N, scanned: N, pulsed: N }` - how many times you were sensed this chronon
- Use to detect if enemies are tracking you

```ruby
detect                   # 2 energy  -> { probed: 1, scanned: 0, pulsed: 2 }
```

### Sensing Delay (Important!)

**All sensing results are delayed by one chronon.** Think of it like a radar ping: you send out a signal, it travels to the target and bounces back, and only then do you see the result. In Rubowar, the "travel time" is exactly one chronon.

When you call `probe()`, `scan()`, or `pulse()`, the action is queued and executed during the current chronon's sense phase, but the results aren't available until your `tick` method runs on the *next* tick.

```
Chronon N:
  1. Your act() reads probe_result    → contains results from Chronon N-1's probe
  2. You call probe(:position)          → queued for this chronon's sense phase
  3. Sense phase executes probe         → result stored internally

Chronon N+1:
  1. Your act() reads probe_result    → NOW contains Chronon N's results
```

**Pattern for using sensing:**

```ruby
def act
  # FIRST: Read results from PREVIOUS tick's sensing
  if probe_result && probe_result[:x]
    # We have a target! Aim and fire
    target_angle = angle_to(probe_result[:x], probe_result[:y])
    turret_diff = normalize_angle(target_angle - turret_angle)
    rotate_turret(turret_diff.clamp(-20, 20))
    fire(10) if turret_diff.abs < 15
  end

  # THEN: Queue sensing for NEXT tick
  probe(:position, :velocity)
end
```

**Common mistake - checking results immediately (this won't work):**

```ruby
def act
  probe(:position)           # Queued for execution
  if probe_result[:x]        # WRONG! This is LAST tick's result, not the probe we just queued
    fire(10)
  end
end
```

**Why the delay?** Two reasons:

1. **Realism**: Like a real radar ping, there's a round-trip time. You send the signal out, it hits the target, and the echo returns. In Rubowar, this takes one chronon.

2. **Fairness**: Sensing is processed in phases. All rubots queue their sensing actions, then all probes/scans/pulses execute simultaneously. This prevents spawn-order from affecting who "sees" first. Everyone's radar pings go out at the same time, and everyone gets their echoes back at the same time.

**Special case - `detect()`:** Unlike other sensing, `detect()` reports counts from the *current* tick's sense phase. It runs last in the sense phase so it can count how many times other rubots probed/scanned/pulsed you this chronon. The result is still read on the next chronon, but it reflects current-chronon sensing activity.

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
| `:small` | 16 | 80 | +8/chronon | 0.64 |
| `:medium` | 20 | 100 | +10/chronon | 1.0 |
| `:large` | 24 | 120 | +12/chronon | 1.44 |

**Tradeoffs:**
- **Small**: Harder to hit, cheapest thrust, but least HP
- **Medium**: Balanced baseline
- **Large**: Most HP and regen, but expensive to move and easier to hit

## Arena

- **Dimensions**: Variable (default 800x600)
- **Origin**: Bottom-left (0,0)
- **Angles**: 0 = East, 90 = North, 180 = West, 270 = South
- **Friction**: 0.92 default (velocity *= friction each chronon)
- **Max speed**: No hard cap (friction naturally limits sustained speed)

## Physics

### Movement
- `thrust(speed:, angle:)` adds velocity in the specified world direction
- Cost: `(speed/1.5)^2 x mass x direction_multiplier`
- Direction multiplier: 1.0 (same direction) to 2.0 (opposite direction)
- Friction slows rubots each chronon (velocity *= 0.92)

### Bullets
- Travel 18 u/chronon (rubots can outrun bullets with sustained thrust, but it's energy-expensive)
- Spawn at edge of rubot (position + rubot radius + bullet radius)
- Self-damage is possible (your bullets can hit you if you're fast enough)

### Collision Damage
- **Wall**: `2 + mass × impact_speed × 0.5` (momentum-based)
- **Rubot**: `2 + other_mass × closing_speed × 0.5` (momentum-based)

Larger rubots deal more collision damage due to higher mass.

### Wall Bounce
Wall collisions use realistic impulse physics with elasticity 0.2. Larger rubots retain more velocity due to mass advantage against the wall's effective mass:
- **Small** (0.64 mass): ~15% velocity retained
- **Medium** (1.0 mass): ~21% velocity retained
- **Large** (1.44 mass): ~27% velocity retained

Walls absorb most momentum - they can't be used for free direction changes.

## Energons

Energy power-ups that spawn periodically and grow in value over time.

### Mechanics
- **Spawn rate**: Every 50 chronons (configurable)
- **Starting value**: 1 energy
- **Growth**: +1 energy per chronon alive
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
battle = Rubowar::Battle.new([Spinner, Tracker])

# Block-based (real-time)
battle.on(:chronon) { |state| render_frame(state) }
battle.on(:death) { |event| play_sound(:death) }
battle.run

# Collect events (replays)
events = battle.run
save_replay(events)
```

**Event types**: `:chronon`, `:death`, `:error`, `:action_failed`, `:energon_spawn`, `:energon_collect`, `:battle_end`

## Victory

- Last rubot standing wins
- Chronon limit (10,000 chronons) prevents stalemates
- Tiebreaker: most damage dealt, then highest HP percentage

## Error Handling

If rubot code crashes or times out: **10 damage** + skip chronon.

## Project Structure

```
rubowar/
├── lib/
│   ├── rubowar/
│   │   ├── rubot.rb           # Module participants include
│   │   ├── arena.rb           # Physics, collisions
│   │   ├── battle.rb          # Game loop
│   │   ├── rubot_actor.rb    # Mutable state tracking
│   │   ├── rubot_state.rb     # Immutable state snapshots
│   │   ├── arena_state.rb     # Arena state snapshots
│   │   ├── bullet.rb          # Projectile tracking
│   │   ├── energon.rb         # Energy power-ups
│   │   ├── physics.rb         # Physics calculations
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
