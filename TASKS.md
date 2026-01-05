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
- [x] State accessors: `tick_number`, `damage_dealt`, `damage_taken`
- [x] State accessors: `energons`, `size`
- [x] Action method: `thrust(speed:, angle:)` - world coordinates, mass-based cost
- [x] Action method: `turret(degrees)`
- [x] Action method: `fire(energy)`
- [x] Action method: `shield(energy)`
- [x] Action method: `look(*attributes)` - attribute-based costs
- [x] Action queuing system

### Arena (`lib/rubowar/arena.rb`)
- [x] Initialize with configurable width/height (default 800x600)
- [x] Rubot spawning (random positions, min distances)
- [x] Position/velocity tracking for all rubots
- [x] Friction application each tick (0.95 default)
- [x] Wall collision detection + bounce + momentum damage (2 + speed x 0.75)
- [x] Rubot collision detection + push apart + momentum damage (2 + mass x speed x 0.5)
- [x] Max speed enforcement (20 u/tick)
- [x] Thrust processing with mass and direction multiplier
- [x] Look processing with attribute-based costs

### RubotRunner (`lib/rubowar/rubot_runner.rb`)
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
- [x] Movement (18 u/tick)
- [x] Collision detection with rubots
- [x] Out-of-bounds removal
- [x] Spawn at edge of rubot (position + rubot radius + bullet radius)

### Battle (`lib/rubowar/battle.rb`)
- [x] Initialize with rubot classes and arena config
- [x] Game loop structure
- [x] Call rubot `tick` methods
- [x] Process queued actions
- [x] Apply physics (movement, collisions)
- [x] Update bullets
- [x] Event emission system (`on` method for callbacks)
- [x] Victory detection (last standing, tick limit, tiebreakers)

### Terminal Renderer (`lib/rubowar/renderers/terminal.rb`)
- [x] ASCII arena display
- [x] Rubot positions with direction indicator
- [x] Health/energy bars
- [x] Bullet positions
- [x] Battle status output

### Example Rubots (`robots/`)
- [x] `spinner.rb` - Simple turret spinner, fires on sight
- [x] `tracker.rb` - Seeks and tracks enemies with patrol behavior

### Tests
- [x] Rubot module tests
- [x] Arena physics tests
- [x] Bullet tests
- [x] RubotRunner tests

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

### Look System
- [x] Attribute-based look costs
- [x] Base cost: 1 energy (returns x, y)
- [x] `:size`: +1 energy
- [x] `:velocity`: +2 energy
- [x] `:shield`: +2 energy
- [x] `:health`: +3 energy
- [x] `:energy`: +3 energy
- [x] Look returns previous tick's result (1-tick delay)

### Callbacks
- [x] `on_hit(damage, direction)`
- [x] `on_spawn`
- [x] `on_death`
- [x] `on_wall`
- [x] `on_collision(other_rubot)` - receives RubotState
- [x] `on_energon(amount)`

---

## Phase 3: Energons & CLI - NOT STARTED

### Energons (`lib/rubowar/energon.rb`)
- [ ] Spawn logic (every ~150 ticks, max 2)
- [ ] Random energy value (20-80)
- [ ] Collection detection (15 unit radius)
- [ ] `on_energon(amount)` callback triggering
- [ ] `energons` accessor (always visible, free)

### CLI (`bin/rubowar`)
- [ ] Load rubot files
- [ ] Run battle with options (arena size, tick limit)
- [ ] Output results

### Replay System
- [ ] Event log recording
- [ ] JSON serialization

---

## Phase 4: Sandboxing & Safety - NOT STARTED

### Process Isolation (`lib/rubowar/robot_runner.rb`)
- [ ] Subprocess spawning for rubot code
- [ ] JSON state serialization
- [ ] JSON action deserialization
- [ ] Timeout enforcement (10ms/tick)
- [ ] Dangerous method removal

### Error Handling
- [ ] Crash detection → 10 damage + skip tick
- [ ] Timeout detection → 10 damage + skip tick

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
- `MAX_SHIELD = 50`
- `SHIELD_DEGRADATION = 2/tick`

### Movement
- `MAX_SPEED = 20`
- `THRUST_MULTIPLIER = 1.5`
- `DEFAULT_FRICTION = 0.95`

### Collisions
- `COLLISION_BASE_DAMAGE = 2`
- `COLLISION_VELOCITY_MULTIPLIER = 0.5` (rubot)
- `WALL_VELOCITY_MULTIPLIER = 0.75` (wall)

### Sensing
- `TURRET_TURN_DIVISOR = 30.0`
- `LOOK_BASE_COST = 1`
- `LOOK_COSTS = { size: 1, velocity: 2, shield: 2, health: 3, energy: 3 }`

### Bullets
- `SPEED = 18`
- `RADIUS = 3`

---

## Design Reference

See `README.md` for player-facing API documentation.
See `design-doc.md` for full design specification.
