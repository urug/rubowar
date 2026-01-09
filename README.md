# Rubowar

A competitive programming game where Ruby club members write Ruby classes to control robots ("Rubots") that battle in an arena. The engine is a standalone Ruby gem with a pluggable renderer interface.

## Hello World - Simplest Bot

```ruby
class HelloBot
  include Rubowar::Rubot
  size :medium

  def act
    rotate_turret(10)        # Spin turret (1 energy)
    fire(5) if energy > 20   # Fire when we have energy (5 energy)
  end
end

# Run a battle
battle = Rubowar::Battle.new([HelloBot, HelloBot])
battle.run
puts "Winner: #{battle.winner.rubot_class.name}"
```

This bot spins and shoots when it has energy. Medium size regenerates 10 energy/turn, so it stays sustainable!

## Learning Path

**New to Rubowar?** Start with the [Tutorial](TUTORIAL.md) for a hands-on introduction, then study the sample bots in order of complexity:

1. **Spinner** (19 lines) - Stationary turret, learn the basics
2. **Tracker** (36 lines) - Target tracking with SimpleTargeting mixin
3. **Coroner** (200 lines) - Corner camping with state machines
4. **Evader** (213 lines) - Counter-intelligence and evasion tactics
5. **Crusher** (323 lines) - Wall-ramming specialist
6. **Hunter** (326 lines) - Adaptive predator with size-based tactics
7. **Hugger** (452 lines) - Expert wall-hugging minimal movement

See [`SAMPLE_BOTS.md`](SAMPLE_BOTS.md) for detailed explanations of each bot and what you'll learn.

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
| `raise_shields(energy)` | energy | Add to shield (max = HP cap, decays 12%/chronon) |

### Action Processing Order

**Actions are processed in phases, not in the order you call them.** This ensures fairness (no spawn-order advantage) and creates intuitive "move then shoot" behavior.

```
Phase 1: SENSE   → All probe(), scan(), pulse() for all rubots
Phase 2: MOVE    → All thrust(), rotate_turret() for all rubots → physics (movement, collisions)
Phase 3: COMBAT  → All fire(), raise_shields() for all rubots → bullet physics
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

**Estimating thrust cost:**

Use `thrust_cost(thrust_speed:, angle:)` to calculate what a thrust will cost based on your current momentum:

```ruby
def act
  escape_angle = angle_to(target_x: 320, target_y: 320) + 180  # Away from center
  cost = thrust_cost(thrust_speed: 6, angle: escape_angle)

  if cost <= energy - 15  # Reserve 15 for combat
    thrust(speed: 6, angle: escape_angle)
  elsif cost <= energy
    thrust(speed: 6, angle: escape_angle)  # Use all energy to escape
  else
    # Can't afford this maneuver, try a cheaper one
    thrust(speed: 3, angle: velocity_angle || 0)  # Coast with momentum
  end
end
```

The `thrust` method reserves minimum cost (assumes 1.0x multiplier) to allow queueing, but actual cost at execution depends on your momentum. Use `thrust_cost` to plan energy budgets accurately.

### Sensing

| Method | Cost | Returns |
|--------|------|---------|
| `probe(*attributes)` | sum of attribute costs | Line scan in turret direction |
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
probe                        # 1 energy  -> ProbeEcho with size only
probe(:position)             # 5 energy  -> ProbeEcho with size, x, y
probe(:position, :velocity)  # 8 energy  -> ProbeEcho with size, x, y, velocity_x, velocity_y

# Check results next chronon:
probe_echo.found?            # true if target detected
probe_echo.x                 # position (if requested)
probe_echo.velocity_x        # velocity (if requested)
```

**scan() - Multiple targets, position/velocity only:**
- Cost: `3 + ceil(angle/20) + ceil(distance/100)` [+2 for velocity] [+1 for owner]
- Returns ScanEcho containing all rubots and bullets in arc
- Each target is a SenseTarget with x, y, type (:rubot/:bullet)
- With velocity: adds velocity_x, velocity_y
- With owner: adds owner (class name of rubot that fired bullet, nil for rubots)

```ruby
scan(angle: 20, distance: 100)                 # 5 energy
scan(angle: 20, distance: 100, velocity: true) # 7 energy - includes velocity
scan(angle: 90, distance: 300)                 # 11 energy - wide arc scan

# Check results next chronon:
scan_echo.any_rubots?                          # are there any rubots?
scan_echo.rubots                               # filter to only rubots
scan_echo.closest_rubot(to_x: x, to_y: y)      # find nearest rubot
```

**pulse() - Quick 360° awareness ping:**
- Cost: `2 + ceil(distance/75)` [+1 for owner]
- Returns PulseEcho containing all rubots and bullets within radius
- Same API as ScanEcho (any_rubots?, closest_rubot(), etc.)

```ruby
pulse(distance: 75)               # 3 energy
pulse(distance: 100)              # 4 energy
pulse(distance: 100, owner: true) # 5 energy - includes bullet owner info

# Check results next chronon:
pulse_echo.any_rubots?
closest = pulse_echo.closest_rubot(to_x: x, to_y: y)
```

**detect() - Counter-intelligence:**
- Cost: 2 energy
- Returns DetectIntel with probed, scanned, pulsed counts
- Use to detect if enemies are tracking you

```ruby
detect                       # 2 energy

# Check results next chronon:
detect_intel.targeted?       # true if sensed by anyone
detect_intel.probed          # times probed this chronon
```

### Sensing Delay (Important!)

**All sensing results are delayed by one chronon.** Think of it like a radar ping: you send out a signal, it travels to the target and bounces back, and only then do you see the result. In Rubowar, the "travel time" is exactly one chronon.

![Sensing Delay Diagram](docs/sensing-delay.svg)

When you call `probe()`, `scan()`, or `pulse()`, the action is queued and executed during the current chronon's sense phase, but the results aren't available until your `act` method runs on the *next* chronon.

```
Chronon N:
  1. Your act() reads probe_echo    → contains results from Chronon N-1's probe
  2. You call probe(:position)          → queued for this chronon's sense phase
  3. Sense phase executes probe         → result stored internally

Chronon N+1:
  1. Your act() reads probe_echo    → NOW contains Chronon N's results
```

**Sensing Result Objects:**

Results are returned as structured objects with helper methods. They always return empty objects (never nil), so you don't need safe navigation (`&.`):

```ruby
# ProbeEcho - single target result
probe_echo.found?       # Was a target detected?
probe_echo.empty?       # No target found?
probe_echo.x            # Position (if requested)
probe_echo[:x]          # Hash-style access still works

# ScanEcho / PulseEcho - multiple targets
scan_echo.empty?        # No targets found?
scan_echo.rubots        # Filter to only rubots
scan_echo.bullets       # Filter to only bullets
scan_echo.any_rubots?   # Are there any rubots?
scan_echo.closest_rubot(to_x: x, to_y: y)  # Find nearest rubot
scan_echo.each { |t| ... }  # Enumerable support

# DetectIntel - counter-intelligence
detect_intel.targeted?  # Was I sensed by anyone?
detect_intel.probed     # How many times probed
```

**Pattern for using sensing:**

```ruby
def act
  # FIRST: Read results from PREVIOUS chronon's sensing
  # No need for &. - probe_echo is never nil
  if probe_echo.found?
    # We have a target! Aim and fire
    target_angle = angle_to(target_x: probe_echo.x, target_y: probe_echo.y)
    turret_diff = normalize_angle(target_angle - turret_angle)
    rotate_turret(turret_diff.clamp(-20, 20))
    fire(10) if turret_diff.abs < 15
  end

  # THEN: Queue sensing for NEXT chronon
  probe(:position, :velocity)
end
```

**Common mistake - checking results immediately (this won't work):**

```ruby
def act
  probe(:position)           # Queued for execution
  if probe_echo.x            # WRONG! This is LAST chronon's result, not the probe we just queued
    fire(10)
  end
end
```

**Why the delay?** Two reasons:

1. **Realism**: Like a real radar ping, there's a round-trip time. You send the signal out, it hits the target, and the echo returns. In Rubowar, this takes one chronon.

2. **Fairness**: Sensing is processed in phases. All rubots queue their sensing actions, then all probes/scans/pulses execute simultaneously. This prevents spawn-order from affecting who "sees" first. Everyone's radar pings go out at the same time, and everyone gets their echoes back at the same time.

**Special case - `detect()`:** Unlike other sensing actions which report what you sensed in the previous chronon, `detect()` reports counts from the *current* chronon's sense phase. It runs last in the sense phase (after all probe/scan/pulse actions) so it can count how many times other rubots probed/scanned/pulsed you *this* chronon. Like other sensing results, `detect_intel` is read during the *next* chronon's `act()` method, but the data it contains reflects current-chronon sensing activity targeting you.

### Callbacks

```ruby
def on_hit(damage:, direction:)  # Projectile hit
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

- **Dimensions**: Variable (default 640x640)
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

**Event types**: `:chronon`, `:death`, `:error`, `:action_failed`, `:energon_spawn`, `:energon_spawn_failed`, `:energon_collect`, `:battle_end`

## Victory

- Last rubot standing wins
- Chronon limit (10,000 chronons) prevents stalemates
- Tiebreaker: most damage dealt, then highest HP percentage

## Error Handling

If rubot code crashes or times out: **20 damage** + skip chronon.

## Project Structure

```
rubowar/
├── lib/
│   ├── rubowar/
│   │   ├── rubot.rb              # Module participants include
│   │   ├── arena.rb              # Physics, collisions
│   │   ├── battle.rb             # Game loop
│   │   ├── rubot_actor.rb        # Mutable state tracking
│   │   ├── rubot_state.rb        # Immutable state snapshots
│   │   ├── arena_state.rb        # Arena state snapshots
│   │   ├── bullet.rb             # Projectile tracking
│   │   ├── energon.rb            # Energy power-ups
│   │   ├── physics.rb            # Physics calculations
│   │   ├── config.rb             # Game configuration constants
│   │   ├── simple_targeting.rb   # Target tracking mixin
│   │   ├── phases/               # Phase execution modules
│   │   │   ├── sense.rb
│   │   │   ├── move.rb
│   │   │   ├── combat.rb
│   │   │   └── energon.rb
│   │   └── renderers/
│   │       └── terminal.rb       # ASCII visualization
│   └── rubowar.rb
├── test/
├── robots/                       # Example rubots (spinner, tracker, coroner, evader, crusher, hunter, hugger)
├── bin/rubowar                   # CLI (not yet implemented)
└── rubowar.gemspec
```

## License

MIT License - see [LICENSE](LICENSE)
