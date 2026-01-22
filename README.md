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
battle = Rubowar::Battle.local([HelloBot, HelloBot])
battle.run
puts "Winner: #{battle.winner.rubot_class.name}"
```

This bot spins and shoots when it has energy. Medium size regenerates 16 energy/turn, so it stays sustainable!

## Learning Path

**New to Rubowar?** Start with the [Tutorial](docs/TUTORIAL.md) for a hands-on introduction, then study the sample bots in order of complexity:

1. **Spinner** - Stationary turret, learn the basics
2. **Tracker** - Target tracking with SimpleTargeting mixin
3. **Coroner** - Corner camping with state machines
4. **Evader**  - Counter-intelligence and evasion tactics
5. **Crusher** - Wall-ramming specialist
6. **Hunter**  - Adaptive predator with size-based tactics
7. **Hugger**  - Expert wall-hugging minimal movement

See [`SAMPLE_BOTS.md`](docs/SAMPLE_BOTS.md) for detailed explanations of each bot and what you'll learn.

**Running battles?** See [`BATTLES.md`](docs/BATTLES.md) for battle configuration, events, statistics, and reproducible testing.

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

### Quick Reference

| State | Actions | Sensing |
|-------|---------|---------|
| `x`, `y`, `speed` | `thrust(speed:, angle:)` | `probe(*attributes)` |
| `turret_angle` | `rotate_turret(degrees)` | `scan(angle:, distance:)` |
| `health`, `energy` | `fire(energy)` | `pulse(distance:)` |
| `shield_level` | `raise_shields(energy)` | `detect` |

### Actions

| Method | Cost | Effect |
|--------|------|--------|
| `thrust(speed:, angle:)` | (speed/1.5)^2 x mass x direction | Add velocity in world direction |
| `rotate_turret(degrees)` | ceil(\|degrees\|/24) | Rotate turret |
| `fire(energy)` | energy | Damage = 1.5 x energy, bullet speed 18 |
| `raise_shields(energy)` | energy | Add to shield (max = HP cap, decays 12%/chronon) |

### Action Processing Order

Actions are processed in phases, not call order: **SENSE → MOVE → COMBAT**

```
Phase 1: SENSE   → probe(), scan(), pulse(), detect
Phase 2: MOVE    → thrust(), rotate_turret() → physics
Phase 3: COMBAT  → fire(), raise_shields() → bullets
```

Energy is deducted in phase order. See [`API.md`](docs/API.md) for details.

### Sensing

| Method | Cost | Returns |
|--------|------|---------|
| `probe(*attributes)` | sum of attribute costs | Line scan in turret direction |
| `scan(angle:, distance:)` | 3 + area cost | Arc scan for all targets |
| `pulse(distance:)` | 2 + ceil(distance/75) | 360° radar ping |
| `detect` | 2 | Counter-intelligence |

**Sensing delay**: Results are available on the *next* chronon (like a radar ping).

```ruby
probe(:position)                # Queue sensing
# Next chronon:
if probe_echo.found?
  fire(10)  # Target acquired!
end
```

### Callbacks

```ruby
def on_spawn                     # Match start
def on_death                     # Health reached 0
def on_wall                      # Wall collision
def on_hit(damage:, direction:)  # Projectile hit
def on_collision(other:)         # Rubot collision (other is RubotState)
def on_energon(amount:)          # Collected energon
```

### Rubot Sizes

| Size      | Radius | HP  | Energy Regen | Mass |
|-----------|--------|-----|--------------|------|
| `:small`  | 6      | 50  | +7/chronon   | 0.36 |
| `:medium` | 10     | 90  | +16/chronon  | 1.0  |
| `:large`  | 14     | 120 | +18/chronon  | 1.96 |

**Tradeoffs:**
- **Small**: Harder to hit, cheapest thrust, but least HP
- **Medium**: Balanced baseline
- **Large**: Most HP and regen, but expensive to move and easier to hit

See [`API.md`](docs/API.md) for complete API documentation including helper methods, sensing details, and examples.

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

See [`PHYSICS.md`](docs/PHYSICS.md) for detailed physics documentation including formulas and configuration constants.

## Energons

Energy power-ups that spawn periodically and grow in value over time.

### Mechanics
- **Spawn rate**: Every 50 chronons (configurable)
- **Starting value**: 1 energy
- **Growth**: +1 energy per chronon alive
- **Collection**: Touch to collect (4 unit radius)
- **Spawn position**: Maximizes minimum distance from all bots, avoids walls (15% buffer)

### Detection
- `energons` accessor returns `[{x:, y:}]` - always visible, free
- Value is hidden until collected (older = more valuable)
- `energon_spawn_interval` and `energon_growth_rate` tell you the rules

### Strategy
- Early collection = small reward, less risk
- Late collection = big reward, more competition
- Spawns away from corners to discourage camping

## Custom Actors

For advanced use cases (web interfaces, AI training, network play), you can create custom actors that control rubots externally:

```ruby
# Low-level API for custom actors
event_bus = Rubowar::EventBus.new(chronon_limit: 9000)
arena = Rubowar::Arena.new(width: 640, height: 640, event_bus: event_bus)
battle = Rubowar::Battle.new(arena: arena, event_bus: event_bus)
battle.register(Rubowar::LocalActor.new(MyBot))
battle.register(my_custom_actor)  # Your custom actor
battle.run
```

See [`CUSTOM_ACTORS.md`](docs/CUSTOM_ACTORS.md) for the full actor interface, action format, and implementation examples.

## Renderer Interface

The engine emits events for any renderer:

```ruby
battle = Rubowar::Battle.local([Spinner, Tracker])

# Block-based (real-time)
battle.on(:chronon) { |state| render_frame(state) }
battle.on(:death) { |event| play_sound(:death) }
battle.run

# Collect events (replays)
events = battle.run
save_replay(events)
```

**Event types**: `:chronon`, `:death`, `:error`, `:action_failed`, `:energon_spawn`, `:energon_spawn_failed`, `:energon_collect`, `:battle_end`

See [`RENDERERS.md`](docs/RENDERERS.md) for full renderer implementation details, event data structures, and built-in renderers.

## Victory

- Last rubot standing wins
- Chronon limit (9,000 chronons) prevents stalemates
- Tiebreaker: most damage dealt, then highest HP percentage

## Error Handling

If rubot code crashes or times out: **20 damage** + skip chronon.

## Debugging

```ruby
# Quick test against dummy opponents
result = Rubowar.test_battle(MyBot, opponents: [:spinner, :chaser])
puts "Won: #{result[:won]}"

# Watch live
Rubowar.test_battle(MyBot, watch: true)

# Reproducible with seed
result = Rubowar.test_battle(MyBot, seed: 12345)
```

**Dummy opponents:** `:stationary`, `:spinner`, `:chaser`, `:random`, `:shielder`

**Debug helpers in your rubot:**
- `status_summary` - One-line status string
- `can_do?(:fire, energy_amount: 20)` - Check affordability
- `action_cost(:thrust, speed: 5, angle: 90)` - Calculate costs
- `dump_sensing` - Print sensing results

See [`DEBUGGING.md`](docs/DEBUGGING.md) for full debugging documentation including test harness options, event logging, and debugging patterns.

For battle configuration (seeding, controlled spawning, statistics), see [`BATTLES.md`](docs/BATTLES.md).

## Command-Line Scripts

Run battles from the command line:

```bash
# Watch a battle in real-time
bin/battle -w rubots/spinner.rb rubots/hunter.rb

# Run 100 battles and see statistics
bin/battle -n 100 rubots/spinner.rb rubots/hunter.rb

# Log a battle to JSON for replay/analysis
bin/log -o replay.json rubots/spinner.rb rubots/hunter.rb

# Run a full tournament
bin/tournament
```

See [`SCRIPTS.md`](docs/SCRIPTS.md) for full documentation of all scripts and options.

## Project Structure

```
rubowar/
├── lib/
│   ├── rubowar/
│   │   ├── rubot.rb              # Module participants include
│   │   ├── arena.rb              # Physics, collisions
│   │   ├── battle.rb             # Game loop
│   │   ├── battle_stats.rb       # Post-battle statistics
│   │   ├── rubot_actor.rb        # Shared actor state/behavior module
│   │   ├── local_actor.rb        # Actor wrapping local Rubot instance
│   │   ├── basic_actor.rb        # Minimal actor for testing/external control
│   │   ├── rubot_state.rb        # Immutable state snapshots
│   │   ├── arena_state.rb        # Arena state snapshots
│   │   ├── bullet.rb             # Projectile tracking
│   │   ├── energon.rb            # Energy power-ups
│   │   ├── physics.rb            # Physics calculations
│   │   ├── config.rb             # Game configuration constants
│   │   ├── simple_targeting.rb   # Target tracking mixin
│   │   ├── test_harness.rb       # Quick testing with dummy opponents
│   │   ├── phases/               # Phase execution modules
│   │   │   ├── sense.rb
│   │   │   ├── move.rb
│   │   │   ├── combat.rb
│   │   │   └── energon.rb
│   │   └── renderers/
│   │       ├── terminal.rb       # ASCII visualization
│   │       ├── json_logger.rb    # JSON serialization for replay
│   │       └── html_canvas.rb    # HTML5 Canvas visualization
│   └── rubowar.rb
├── test/
├── rubots/                       # Example rubots (spinner, tracker, coroner, evader, crusher, hunter, hugger)
├── bin/
│   ├── battle                    # Run battles with various options
│   ├── log                       # Record battles to JSON
│   ├── tournament                # Run full tournament
│   └── console                   # Interactive Ruby console
├── docs/
│   ├── API.md                    # Complete Rubot API reference
│   ├── BATTLES.md                # Battle mechanics, events, statistics
│   ├── CUSTOM_ACTORS.md          # Building custom actors
│   ├── DEBUGGING.md              # Debug tools and testing
│   ├── PHYSICS.md                # Physics system documentation
│   ├── RENDERERS.md              # Renderer interface
│   ├── SAMPLE_BOTS.md            # Sample bot explanations
│   ├── SCRIPTS.md                # CLI scripts
│   ├── TESTING.md                # Test writing guidelines
│   └── TUTORIAL.md               # Hands-on tutorial
└── rubowar.gemspec
```

## License

MIT License - see [LICENSE](LICENSE)
