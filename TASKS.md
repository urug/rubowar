# Rubowar Implementation Tasks

## Phase 1: Core Engine (MVP)

### Project Setup
- [ ] Create `rubowar.gemspec`
- [ ] Create `Gemfile`
- [ ] Create `lib/rubowar.rb` (main entry point)
- [ ] Create `Rakefile` with test task
- [ ] Set up `spec/spec_helper.rb`

### Rubot Module (`lib/rubowar/rubot.rb`)
- [ ] Module inclusion hook (registers robot class)
- [ ] `size` class method (`:small`, `:medium`, `:large`)
- [ ] State accessors: `x`, `y`, `velocity_x`, `velocity_y`, `speed`
- [ ] State accessors: `body_angle`, `turret_angle`
- [ ] State accessors: `health`, `energy`, `shield_level`
- [ ] State accessors: `arena_width`, `arena_height`, `friction`
- [ ] State accessors: `tick_number`, `damage_dealt`, `damage_taken`
- [ ] State accessors: `energons`, `size`
- [ ] Action method: `thrust(energy)`
- [ ] Action method: `turn(degrees)`
- [ ] Action method: `turret(degrees)`
- [ ] Action method: `fire(energy)`
- [ ] Action method: `look(energy)` (basic version)
- [ ] Action queuing system

### Arena (`lib/rubowar/arena.rb`)
- [ ] Initialize with configurable width/height (default 800x600)
- [ ] Robot spawning (random positions, min distances)
- [ ] Position/velocity tracking for all robots
- [ ] Friction application each tick
- [ ] Wall collision detection + bounce + 10 damage
- [ ] Robot collision detection + push apart + 5 damage
- [ ] Max speed enforcement (20 u/tick)

### Bullet (`lib/rubowar/bullet.rb`)
- [ ] Position, velocity, owner, damage tracking
- [ ] Movement (18 u/tick)
- [ ] Collision detection with robots
- [ ] Out-of-bounds removal

### Match (`lib/rubowar/match.rb`)
- [ ] Initialize with robot classes and arena config
- [ ] Game loop structure
- [ ] Call robot `tick` methods
- [ ] Process queued actions
- [ ] Apply physics (movement, collisions)
- [ ] Update bullets
- [ ] Event emission system (`on` method for callbacks)
- [ ] Victory detection (last standing, tick limit, tiebreakers)

### Terminal Renderer (`lib/rubowar/renderers/terminal.rb`)
- [ ] ASCII arena display
- [ ] Robot positions with direction indicator
- [ ] Health/energy bars
- [ ] Bullet positions
- [ ] Match status output

### Example Robots (`robots/`)
- [ ] `spinner.rb` - Simple turret spinner, fires on sight
- [ ] `tracker.rb` - Seeks and tracks enemies

### Specs
- [ ] Rubot module specs
- [ ] Arena physics specs
- [ ] Bullet specs
- [ ] Match runner specs

---

## Phase 2: Full Sensing & Combat

### Enhanced Sensing
- [ ] `look(energy)` with tiered detail (1-5 energy levels)
- [ ] `scan(width)` cone scan with bullet detection
- [ ] `pulse(radius)` circle scan

### Shield System
- [ ] `shield(energy)` action
- [ ] Shield degradation (2/tick)
- [ ] Damage absorption logic
- [ ] Max shield (50)

### Callbacks
- [ ] `on_hit(damage, direction)`
- [ ] `on_spawn`
- [ ] `on_death`
- [ ] `on_wall`
- [ ] `on_collision(robot)`

### Robot Sizes
- [ ] Size-based collision damage modifiers
- [ ] Size-based energy regeneration
- [ ] Size-based radius for collision

---

## Phase 3: Energons & Polish

### Energons (`lib/rubowar/energon.rb`)
- [ ] Spawn logic (every ~150 ticks, max 2)
- [ ] Random energy value (20-80)
- [ ] Collection detection (15 unit radius)
- [ ] `on_energon(amount)` callback
- [ ] `energons` accessor (always visible, free)

### CLI (`bin/rubowar`)
- [ ] Load robot files
- [ ] Run match with options (arena size, tick limit)
- [ ] Output results

### Replay System
- [ ] Event log recording
- [ ] JSON serialization

---

## Phase 4: Sandboxing & Safety

### Process Isolation (`lib/rubowar/robot_runner.rb`)
- [ ] Subprocess spawning for robot code
- [ ] JSON state serialization
- [ ] JSON action deserialization
- [ ] Timeout enforcement (10ms/tick)
- [ ] Dangerous method removal

### Error Handling
- [ ] Crash detection → 10 damage + skip tick
- [ ] Timeout detection → 10 damage + skip tick

---

## Design Reference

See `README.md` for complete API documentation.

Full design spec available at: `~/.claude/plans/mutable-yawning-pascal.md`
