# Rubowar Implementation Tasks

## Phase 1: Core Engine (MVP) - COMPLETE

### Project Setup
- [x] Create `rubowar.gemspec`
- [x] Create `Gemfile`
- [x] Create `lib/rubowar.rb` (main entry point)
- [x] Create `Rakefile` with test task
- [x] Set up `test/test_helper.rb`

### Rubot Module (`lib/rubowar/rubot.rb`)
- [x] Module inclusion hook (registers rubot class)
- [x] `size` class method (`:small`, `:medium`, `:large`)
- [x] State accessors: `x`, `y`, `velocity_x`, `velocity_y`, `speed`
- [x] State accessors: `turret_angle`
- [x] State accessors: `health`, `energy`, `shield_level`
- [x] State accessors: `arena_width`, `arena_height`, `friction`
- [x] State accessors: `chronons`, `damage_dealt`, `damage_taken`
- [x] State accessors: `energons`, `size`
- [x] Action method: `thrust(speed:, angle:)` - world coordinates, mass-based cost
- [x] Action method: `turret(degrees)`
- [x] Action method: `fire(energy)`
- [x] Action method: `shield(energy)`
- [x] Action method: `probe(*attributes)` - attribute-based costs
- [x] Action queuing system

### Arena (`lib/rubowar/arena.rb`)
- [x] Initialize with configurable width/height (default 800x600)
- [x] Rubot spawning (random positions, min distances)
- [x] Position/velocity tracking for all rubots
- [x] Friction application each chronon (0.95 default)
- [x] Wall collision detection + bounce + momentum damage (2 + speed x 0.75)
- [x] Rubot collision detection + push apart + momentum damage (2 + mass x speed x 0.5)
- [x] Max speed enforcement (20 u/chronon)
- [x] Thrust processing with mass and direction multiplier
- [x] Probe processing with attribute-based costs

### RubotActor (`lib/rubowar/rubot_actor.rb`)
- [x] Size-based stats: radius, energy_regen, max_health
- [x] Position, velocity, turret_angle tracking
- [x] Health, energy, shield_level tracking
- [x] Damage dealt/taken tracking
- [x] `apply_damage` with shield absorption
- [x] `spend_energy` with failure penalty
- [x] `regenerate_energy` and `degrade_shield`
- [x] `clamp_speed` for max speed enforcement

### State Objects
- [x] `RubotState` - immutable Data.define snapshot
- [x] `ArenaState` - immutable Data.define snapshot

### Bullet (`lib/rubowar/bullet.rb`)
- [x] Position, velocity, owner, damage tracking
- [x] Movement (18 u/chronon)
- [x] Collision detection with rubots
- [x] Out-of-bounds removal
- [x] Spawn at edge of rubot (position + rubot radius + bullet radius)

### Battle (`lib/rubowar/battle.rb`)
- [x] Initialize with rubot classes and arena config
- [x] Game loop structure
- [x] Call rubot `act` methods
- [x] Process queued actions
- [x] Apply physics (movement, collisions)
- [x] Update bullets
- [x] Event emission system (`on` method for callbacks)
- [x] Victory detection (last standing, chronon limit, tiebreakers)

### Terminal Renderer (`lib/rubowar/renderers/terminal.rb`)
- [x] ASCII arena display
- [x] Rubot positions with direction indicator
- [x] Health/energy bars
- [x] Bullet positions
- [x] Battle status output

### Example Rubots (`robots/`)
- [x] `spinner.rb` - Stationary turret spinner, fires on sight
- [x] `coroner.rb` - Corner-camping sniper with lead calculation
- [x] `crusher.rb` - Large ramming tank, no bullets
- [x] `hunter.rb` - Small pursuit predator with intercept logic
- [x] `patroller.rb` - Perimeter patrol with wall-based energon collection
- [x] `avoider.rb` - Evasive bot with energon collection and detect usage

### Tests
- [x] Rubot module tests
- [x] Arena physics tests
- [x] Bullet tests
- [x] RubotActor tests

---

## Phase 2: Balance & Polish - COMPLETE

### Movement System
- [x] Remove `body_angle` - rubots no longer have body direction
- [x] Remove `turn(degrees)` action
- [x] `thrust(speed:, angle:)` with world coordinates
- [x] Mass-based thrust cost: `(speed/1.5)^2 x mass x direction_multiplier`
- [x] Direction multiplier: 1.0 (same) to 2.0 (opposite)
- [x] Partial thrust when insufficient energy

### Size Balance
- [x] Size-based HP: small=80, medium=100, large=120
- [x] Size-based mass derived from radius: `(radius/20)^2`
- [x] Size-based energy regen: small=8, medium=10, large=12

### Collision System
- [x] Momentum-based rubot collision: `2 + mass x speed x 0.5`
- [x] Speed-based wall collision: `2 + speed x 0.75`

### Probe System
- [x] Attribute-based probe costs
- [x] Base cost: 1 energy (returns x, y)
- [x] `:size`: +1 energy
- [x] `:velocity`: +2 energy
- [x] `:shield`: +2 energy
- [x] `:health`: +3 energy
- [x] `:energy`: +3 energy
- [x] Probe returns previous tick's result (1-chronon delay)

### Scan System
- [x] `scan(angle:, distance:, velocity:)` arc scan method
- [x] Cost: `3 + ceil(angle/20) + ceil(distance/100)` [+2 for velocity]
- [x] Returns all rubots and bullets in arc
- [x] Base result: `{x:, y:, type:}`, with velocity: adds `velocity_x`, `velocity_y`
- [x] Scan returns previous tick's result (1-chronon delay)

### Pulse System
- [x] `pulse(distance:)` omnidirectional radar method
- [x] Cost: `2 + ceil(distance/75)`
- [x] Returns all rubots and bullets within radius
- [x] Result: `{x:, y:, type:}` (position only, no velocity)
- [x] Pulse returns previous tick's result (1-chronon delay)

### Callbacks
- [x] `on_hit(damage, direction)`
- [x] `on_spawn`
- [x] `on_death`
- [x] `on_wall`
- [x] `on_collision(other_rubot)` - receives RubotState
- [x] `on_energon(amount)`

---

## Phase 3: Energons & CLI - PARTIAL

### Energons (`lib/rubowar/energon.rb`) - COMPLETE
- [x] Spawn logic (every 80 chronons, configurable via ENERGON_SPAWN_INTERVAL)
- [x] Time-based value: starts at 1, grows +1/chronon (configurable via GROWTH_RATE)
- [x] Collection detection (8 unit radius, touch to collect)
- [x] `on_energon(amount)` callback triggering
- [x] `energons` accessor (always visible, free) - returns `[{x:, y:}]`
- [x] Wall buffer: 15% of smaller arena dimension (spawns away from edges)
- [x] Max-min distance spawn algorithm (spawns equidistant from all bots)
- [x] `energon_spawn_interval` and `energon_growth_rate` accessors for rubots

### Detect Action - COMPLETE
- [x] `detect` counter-intelligence action (2 energy)
- [x] Returns `{ probed:, scanned:, pulsed: }` counts from current tick
- [x] Processed during sense phase with other sensing actions

### CLI (`bin/rubowar`) - NOT STARTED
- [ ] Load rubot files
- [ ] Run battle with options (arena size, chronon limit)
- [ ] Output results

### Replay System - NOT STARTED
- [ ] Event log recording
- [ ] JSON serialization

---

## Phase 4: Sandboxing & Safety - NOT STARTED

### Process Isolation (`lib/rubowar/rubot_actor.rb`)
- [ ] Subprocess spawning for rubot code
- [ ] JSON state serialization
- [ ] JSON action deserialization
- [ ] Timeout enforcement (10ms/chronon)
- [ ] Dangerous method removal

### Error Handling
- [ ] Crash detection → 10 damage + skip chronon
- [ ] Timeout detection → 10 damage + skip chronon

---

## Current Balance Constants

### Sizes
| Size | Radius | HP | Regen | Mass |
|------|--------|-----|-------|------|
| Small | 15 | 80 | 8 | 0.56 |
| Medium | 20 | 100 | 10 | 1.0 |
| Large | 25 | 120 | 12 | 1.56 |

### Combat
- `FIRE_DAMAGE_MULTIPLIER = 1.5`
- `MAX_SHIELD = max_health` (80/100/120 by size)
- `SHIELD_DECAY_RATE = 0.12` (12% per chronon)

### Movement
- `MAX_SPEED = 30`
- `THRUST_MULTIPLIER = 1.5`
- `DEFAULT_FRICTION = 0.95`

### Collisions
- `COLLISION_BASE_DAMAGE = 2`
- `COLLISION_VELOCITY_MULTIPLIER = 0.5` (rubot)
- `WALL_VELOCITY_MULTIPLIER = 0.75` (wall damage)
- `WALL_BOUNCE_COEFFICIENT = 0.12` (velocity retention = mass x 0.12)

### Sensing
- `TURRET_TURN_DIVISOR = 30.0`
- `PROBE_BASE_COST = 1`
- `PROBE_COSTS = { size: 1, position: 4, velocity: 3, turret_angle: 2, shield: 2, health: 3, energy: 3 }`
- `SCAN_BASE_COST = 3`
- `SCAN_ANGLE_DIVISOR = 20.0`
- `SCAN_DISTANCE_DIVISOR = 100.0`
- `SCAN_VELOCITY_COST = 2`
- `SCAN_OWNER_COST = 1`
- `PULSE_BASE_COST = 2`
- `PULSE_DISTANCE_DIVISOR = 75.0`
- `PULSE_OWNER_COST = 1`
- `DETECT_COST = 2`

### Energons
- `ENERGON_SPAWN_INTERVAL = 80`
- `ENERGON_WALL_BUFFER_RATIO = 0.15`
- `ENERGON_INITIAL_VALUE = 1`
- `ENERGON_GROWTH_RATE = 1.0`
- `ENERGON_RADIUS = 8`

### Bullets
- `SPEED = 18`
- `RADIUS = 3`

---

## Design Reference

See `README.md` for player-facing API documentation.
See `design-doc.md` for full design specification.
