# Rubowar: Ruby Robot Battle Arena

## Overview
A competitive programming game where Ruby club members write Ruby classes to control robots ("Rubots") that battle in an arena. The engine is a standalone Ruby gem with a pluggable renderer interface - bring your own visualization (terminal, web, desktop app, etc.).

---

## Core Design Decisions

### Rubot API
```ruby
class Destructo
  include Rubowar::Rubot
  size :medium  # :small, :medium, or :large

  def on_spawn
    @heading = rand(360)
  end

  def tick
    # Access state via methods: energy, health, x, y, turret_angle, etc.
    # Call action methods directly: thrust, fire, turret, probe, shield
    # Actions are queued internally and executed after tick returns
  end

  # Optional callbacks
  def on_hit(damage, direction)
  end

  def on_spawn
  end

  def on_death
  end
end
```

**Error Handling**: If a rubot's code crashes or times out, it takes **10 damage** and skips that tick. This encourages robust code without instant disqualification.

### Rubot Module - Complete API

#### Rubot Size (chosen at class definition)

```ruby
class MyRubot
  include Rubowar::Rubot
  size :medium  # :small, :medium, or :large
end
```

| Size | Radius | HP | Energy Regen | Mass |
|------|--------|-----|--------------|------|
| `:small` | 15 units | 80 | +8/tick | 0.56 |
| `:medium` | 20 units | 100 | +10/tick | 1.0 |
| `:large` | 25 units | 120 | +12/tick | 1.56 |

**Mass** is derived from radius: `(radius / 20)^2` where 20 is the medium radius.

**Tradeoffs:**
- **Small**: 2.8x harder to hit by area, cheapest thrust (mass 0.56), but only 80 HP
- **Medium**: Balanced baseline
- **Large**: 120 HP tank, highest firepower when stationary, but 1.56x thrust cost and easy target

#### State Accessors (read-only)
| Method | Type | Description |
|--------|------|-------------|
| `x`, `y` | Float | Current position in arena |
| `velocity_x`, `velocity_y` | Float | Current velocity vector |
| `speed` | Float | Magnitude of velocity (convenience) |
| `turret_angle` | Float | Direction turret points (0-360°, world coordinates) |
| `health` | Integer | Current HP (varies by size: 80/100/120) |
| `energy` | Integer | Current energy (max 100, regen varies by size) |
| `shield_level` | Integer | Current shield level (0 = no shield, decays 12%/tick, max = HP cap) |
| `arena_width`, `arena_height` | Integer | Arena dimensions |
| `friction` | Float | Arena friction coefficient (default 0.95) |
| `tick_number` | Integer | Current game tick |
| `damage_dealt` | Integer | Total damage dealt this match |
| `damage_taken` | Integer | Total damage received this match |
| `energons` | Array | All energon positions `[{x:, y:}]` (always visible, free) |
| `size` | Symbol | Rubot's size (`:small`, `:medium`, `:large`) |
| `live_rubot_count` | Integer | Number of rubots still alive in battle |
| `energon_spawn_interval` | Integer | Ticks between energon spawns (default 80) |
| `energon_growth_rate` | Float | Energy growth per tick (default 1.0) |

#### Action Methods
| Method | Cost | Description |
|--------|------|-------------|
| `thrust(speed:, angle:)` | (speed/1.5)^2 x mass x direction | Add velocity in world direction |
| `turret(degrees)` | \|degrees\|/30 energy | Rotate turret. Negative = left, positive = right. |
| `fire(energy)` | energy spent | Fire projectile. Damage = **1.5 x energy**. Bullets travel 18 u/tick. |
| `shield(energy)` | energy spent | Pump energy into shield. Decays 12%/tick. Max = HP cap. |
| `probe(*attributes)` | 1 + attribute costs | Line in turret direction. Returns target info or nil. |
| `scan(angle:, distance:, velocity:, owner:)` | 3 + area cost [+2] [+1] | Arc scan for multiple targets. |
| `pulse(distance:, owner:)` | 2 + ceil(distance/75) [+1] | Omnidirectional radar ping. |
| `detect` | 2 | Counter-intelligence: how many times you were sensed. |

**Thrust mechanics:**
- `angle` is in world coordinates (0° = East, 90° = North)
- Cost formula: `(speed / 1.5)^2 x mass x direction_multiplier`
- Direction multiplier: 1.0 (same direction as current velocity) to 2.0 (opposite direction)
- If insufficient energy for full thrust, you get partial thrust and energy drains to zero

**Turret cost examples**: `turret(90)` costs 3 energy, `turret(-45)` costs 1.5 energy

#### Sensing System

**`probe(*attributes)`** - Line scan in turret direction

| Attribute | Cost | Returns |
|-----------|------|---------|
| (base) | 1 | size (:small/:medium/:large) - detection ping |
| `:position` | +4 | x, y coordinates |
| `:velocity` | +3 | velocity_x, velocity_y |
| `:turret_angle` | +2 | turret_angle |
| `:shield` | +2 | shield_level |
| `:health` | +3 | health |
| `:energy` | +3 | energy |

```ruby
probe                    # 1 energy  -> {size: :medium} or {} if no target
probe(:position)         # 5 energy  -> {size: :medium, x: 400, y: 300}
probe(:position, :velocity)  # 8 energy  -> {size:, x:, y:, velocity_x:, velocity_y:}
probe(:position, :velocity, :shield, :health, :energy)  # 16 energy -> everything
```

**Important:** `probe()` returns the result from the PREVIOUS tick's probe. Since actions are processed after tick(), the current probe result won't be available until the next tick.

**`scan(angle:, distance:, velocity: false)`** - Arc scan centered on turret direction

Scans an arc in front of the turret and returns ALL rubots and bullets within the arc.

| Parameter | Description |
|-----------|-------------|
| `angle:` | Arc width in degrees (centered on turret direction) |
| `distance:` | Maximum range in units |
| `velocity:` | Include velocity data (+2 energy) |

**Cost formula:** `3 + ceil(angle/20) + ceil(distance/100)` [+2 for velocity]

**Returns:** Array of `{ x:, y:, type: :rubot/:bullet }` or with velocity `{ x:, y:, velocity_x:, velocity_y:, type: }`

```ruby
scan(angle: 20, distance: 100)                 # 5 energy  -> [{x:, y:, type:}, ...]
scan(angle: 20, distance: 100, velocity: true) # 7 energy  -> [{x:, y:, velocity_x:, velocity_y:, type:}, ...]
scan(angle: 90, distance: 300)                 # 11 energy -> wide area scan
scan(angle: 180, distance: 400)                # 16 energy -> hemisphere scan
```

**Design rationale:** `scan()` provides broad situational awareness (where are things moving?). Use `probe()` for detailed info (health, shield, energy) on a specific target. Like `probe()`, results are from the PREVIOUS tick.

**`pulse(distance:)`** - Omnidirectional radar ping

Quick 360° detection around the rubot. Simpler and cheaper than scan() but position-only.

| Parameter | Description |
|-----------|-------------|
| `distance:` | Radius of detection circle in units |

**Cost formula:** `2 + ceil(distance/75)`

**Returns:** Array of `{ x:, y:, type: :rubot/:bullet }` for everything within radius.

```ruby
pulse(distance: 75)   # 3 energy  -> [{x:, y:, type:}, ...]
pulse(distance: 100)  # 4 energy
pulse(distance: 200)  # 5 energy
```

**Design rationale:** `pulse()` is the cheapest way to detect nearby threats. Use it for quick awareness checks. No velocity data available - if you need that, use `scan()`. Like other sensing methods, results are from the PREVIOUS tick.

**`detect`** - Counter-intelligence

Reports how many times you were probed, scanned, or pulsed in the current tick's sense phase.

**Cost:** 2 energy

**Returns:** `{ probed: N, scanned: N, pulsed: N }`

```ruby
detect                   # 2 energy  -> { probed: 1, scanned: 0, pulsed: 2 }
```

**Use cases:**
- Detect if enemies are actively tracking you
- Trigger evasive maneuvers when being targeted
- Identify aggressive pursuers vs passive bots

#### Shield System

Shields absorb damage before health. They use proportional decay, making high shields expensive to maintain.

**Mechanics**:
- `shield(energy)` - Add energy to shield strength
- Shield decays **12% per tick** (proportional decay)
- Damage hits shield first, then health when shield = 0
- Shield absorbs damage 1:1 (10 damage removes 10 shield)
- Max shield = max HP (80/100/120 by size)

**Decay Examples**:
- 100 shield → 88 → 77 → 68 → 60 → 53 → 47 → 41...
- To maintain 100 shield: costs 12 energy/tick
- To maintain 50 shield: costs 6 energy/tick
- To maintain 20 shield: costs ~2.4 energy/tick

**Max Sustainable Shield** (all regen to shields):
- Small (8 regen): 67 shield
- Medium (10 regen): 83 shield
- Large (12 regen): 100 shield

**Example**:
```ruby
def tick
  # Burst shield when under attack (decays quickly but absorbs hits)
  shield(30) if under_fire?

  # Light sustained shield (costs ~2.4 energy/tick to maintain ~20)
  shield(3) if shield_level < 20 && !under_fire?
end
```

**Strategy**: Shields are tactical burst protection. You can spike to high shields to survive an attack, but they decay quickly. Nobody can sustain max shield while also fighting.

#### Physics

- **Movement**: `thrust(speed:, angle:)` adds velocity in world direction. Cost = (speed/1.5)^2 x mass x direction_multiplier.
- **Friction**: Velocity *= 0.95 each tick (configurable per tournament).
- **Max speed**: Capped at 20 units/tick.
- **Projectiles**: Travel at **18 units/tick** (slightly slower than max rubot speed). Spawn at edge of rubot (position + rubot radius + bullet radius). Can hit anyone including the shooter.
- **Wall collision**: `2 + speed x 0.75` damage + momentum-absorbing bounce. At max speed: 17 damage. Bounce retains velocity x mass x 0.12 (small: 7%, medium: 12%, large: 19%).
- **Rubot collision**: `2 + attacker_mass x attacker_speed x 0.5` damage + push apart. Momentum-based.

#### Callbacks
```ruby
def on_hit(damage, direction)    # Called when taking damage from projectile
def on_spawn                     # Called at match start
def on_death                     # Called when health reaches 0
def on_wall                      # Called on wall collision
def on_collision(other_rubot)    # Called on rubot collision, receives other rubot's state
def on_energon(amount)           # Called when collecting energon (20-80 energy)
```

### Arena

**Dimensions**: Variable (default 800x600 units)
- Configurable per match/tournament
- Rubots access via `arena_width` and `arena_height` accessors

**Coordinate System**:
- Origin (0,0) at **bottom-left** corner
- X increases rightward (0 to arena_width)
- Y increases upward (0 to arena_height)
- **0° = Right (East)**, 90° = Up, 180° = Left, 270° = Down

**Spawning**:
- **Random positions** at match start
- Minimum distance from walls (50 units)
- Minimum distance between rubots (100 units)
- Random starting turret angle

**Players**: 2-4 rubots per match (1v1, 1v1v1, 1v1v1v1, or 2v2)

### Energons

Energy power-ups that spawn periodically and grow in value over time. No healing - damage is permanent.

**Spawn mechanics:**
- Spawn every 80 ticks (configurable via `ENERGON_SPAWN_INTERVAL`)
- Position maximizes minimum distance from all alive rubots
- Wall buffer: 15% of smaller arena dimension (spawns away from edges/corners)
- No limit on number of energons on field

**Value mechanics:**
- Starting value: 1 energy
- Growth: +1 energy per tick alive (configurable via `GROWTH_RATE`)
- Older energons are more valuable but may have more competition

**Collection:**
- Touch to collect (8 unit radius)
- Energy is capped at 100 even with energons
- `on_energon(amount)` callback fires when collected

**Detection:**
- `energons` accessor returns `[{x:, y:}]` - always visible, free
- `energon_spawn_interval` and `energon_growth_rate` tell you the rules
- The actual energy amount is hidden until collected

**Strategy implications:**
- Early collection = small reward, less risk
- Late collection = big reward, more competition
- Spawns away from corners to discourage camping
- Mobile bots can collect more than stationary campers

### Victory Condition
- Last rubot standing wins
- Matches have a tick limit (e.g., 5000 ticks) to prevent stalemates
- If time expires: highest HP wins, then most damage dealt

---

## Architecture

### Project Structure
```
rubowar/
├── lib/
│   ├── rubowar/
│   │   ├── rubot.rb           # The module participants include
│   │   ├── arena.rb           # Game world, physics, collision
│   │   ├── battle.rb          # Runs a single battle
│   │   ├── rubot_runner.rb    # Mutable state tracking
│   │   ├── rubot_state.rb     # Immutable state snapshots (Data.define)
│   │   ├── arena_state.rb     # Arena state snapshots (Data.define)
│   │   ├── bullet.rb          # Projectile tracking
│   │   ├── energon.rb         # Energy power-ups
│   │   ├── sensing_costs.rb   # Sensing cost calculations
│   │   └── renderers/
│   │       └── terminal.rb    # ASCII visualization
│   └── rubowar.rb
├── test/
├── robots/                    # Example rubots for learning
│   ├── spinner.rb             # Stationary turret spinner
│   ├── coroner.rb             # Corner-camping sniper
│   ├── crusher.rb             # Ramming tank
│   ├── hunter.rb              # Pursuit predator
│   ├── patroller.rb           # Perimeter patrol
│   └── avoider.rb             # Evasive bot with energon collection
├── bin/
│   └── rubowar                # CLI to run battles
├── Gemfile
├── rubowar.gemspec
└── README.md
```

### Renderer Interface

The engine is renderer-agnostic. It emits events that any renderer can consume:

```ruby
battle = Rubowar::Battle.new(rubots: [Spinner, Tracker], width: 800, height: 600)

# Option 1: Block-based (for real-time renderers)
battle.on(:tick) { |state| render_frame(state) }
battle.on(:hit) { |event| play_sound(:hit) }
battle.on(:death) { |event| show_explosion(event) }
battle.run

# Option 2: Collect all events (for replays)
events = battle.run  # Returns array of all events
save_replay(events)

# Option 3: Simple terminal output (built-in)
battle.run(renderer: Rubowar::Renderers::Terminal)
```

**Event Types**:
- `:tick` - Full game state each tick
- `:fire` - Rubot fired a projectile
- `:hit` - Projectile hit a rubot
- `:death` - Rubot destroyed
- `:wall_collision` - Rubot hit wall
- `:rubot_collision` - Rubots collided
- `:energon_spawn` - Energon appeared
- `:energon_collect` - Rubot collected energon
- `:battle_end` - Battle concluded with winner

### Key Components

#### 1. Rubot Module (`lib/rubowar/rubot.rb`)
- Included by participant classes
- Provides `size` class method for choosing rubot size
- Delegates state accessors to RubotState and ArenaState
- Provides action methods: `thrust`, `turret`, `fire`, `shield`, `probe`
- Actions are queued and processed after tick returns

#### 2. Arena (`lib/rubowar/arena.rb`)
- Manages physics: movement, friction, collisions
- Processes actions: thrust, turret, fire, shield, probe
- Handles bullet updates and hit detection
- Constants for game balance (damage multipliers, costs, etc.)

#### 3. Battle (`lib/rubowar/battle.rb`)
- Runs game loop: spawn, tick, process actions, update physics
- Emits events via callbacks (renderer-agnostic)
- Determines winner

#### 4. RubotRunner (`lib/rubowar/rubot_runner.rb`)
- Mutable state tracker for game engine
- Tracks position, velocity, health, energy, shield, damage stats
- Provides methods: `apply_damage`, `spend_energy`, `regenerate_energy`, etc.

#### 5. State Objects (`rubot_state.rb`, `arena_state.rb`)
- Immutable snapshots using `Data.define`
- Passed to rubot instances each tick
- Prevents rubots from cheating by modifying state directly

---

## Balance Summary

### Size Comparison

| Metric | Small | Medium | Large |
|--------|-------|--------|-------|
| HP | 80 | 100 | 120 |
| Radius | 15 | 20 | 25 |
| Mass | 0.56 | 1.0 | 1.56 |
| Regen | 8/tick | 10/tick | 12/tick |
| Thrust @ speed 5 | 6.2 energy | 11.1 energy | 17.4 energy |
| Sustainable speed | 5.7 | 4.7 | 4.2 |
| Hit area ratio | 1.0x | 1.8x | 2.8x |

### Damage Output (stationary, all energy to fire)
- Small: 8 x 1.5 = 12 damage/tick
- Medium: 10 x 1.5 = 15 damage/tick
- Large: 12 x 1.5 = 18 damage/tick

### Collision Damage @ Max Speed (20)
- Small hitting: 2 + 0.56 x 20 x 0.5 = 8 damage
- Medium hitting: 2 + 1.0 x 20 x 0.5 = 12 damage
- Large hitting: 2 + 1.56 x 20 x 0.5 = 18 damage

---

## Example Rubots & Strategy Analysis

The example rubots demonstrate five distinct competitive strategies. Tournament results across 3120 battles (1v1, 1v1v1, 1v1v1v1, and 5-way formats):

| Rank | Bot | Win Rate | Strategy |
|------|-----|----------|----------|
| 1 | Coroner | 43.8% | Corner camping sniper |
| 2 | Spinner | 23.6% | Stationary turret spinner |
| 3 | Crusher | 16.4% | Ramming tank |
| 4 | Hunter | 8.4% | Pursuit predator |
| 5 | Patroller | 7.5% | Perimeter patrol |

### Spinner (Simplest - 15 lines)

**Strategy**: Stand still, spin turret, fire when probe hits.

```ruby
class Spinner
  include Rubowar::Rubot
  size :medium

  def tick
    turret(7)
    target = probe
    fire(10) if target && energy > 20
  end
end
```

**Why it works**: Zero movement cost means all energy goes to offense. Probe is cheap (4-7 energy). Only fires when target confirmed - no wasted shots. Exploits aggressive bots that come to it.

**Key insight**: Turret rotation speed of 7°/tick is optimal. Slower = more shots per target pass. Faster = might skip targets between ticks.

| Turret Speed | Performance |
|--------------|-------------|
| 3°/tick | Best avg points, slow coverage |
| 7°/tick | Best balance (chosen) |
| 15°/tick | Fast coverage, fewer hits |

### Coroner (Dominant - Corner Sniper)

**Strategy**: Find a corner, face center, sweep turret, snipe with lead calculation.

**Key behaviors**:
1. Move to nearest corner at spawn
2. Position at safe distance from walls
3. Sweep turret across arena center
4. Track targets with probe, calculate lead for moving targets
5. Fire high-power shots (12-14 damage)

**Why it dominates**:
- Corner position limits approach angles (enemies can only come from ~90° arc)
- Stationary = perfect accuracy + all energy to offense
- Lead calculation hits moving targets reliably
- In multi-bot chaos, lets others fight while sniping survivors

**Performance by format**:
| Format | Win Rate |
|--------|----------|
| 1v1 | 30% |
| 1v1v1 | 45% |
| 1v1v1v1 | 58% |
| 5-way | 68% |

Coroner scales with chaos - more bots = more targets to snipe while they fight each other.

### Crusher (Ramming Tank)

**Strategy**: Large size, find target with pulse, chase and ram. No bullets.

```ruby
size :large  # 120 HP, high collision damage

def chase_and_ram
  # Speed and shields scale with distance
  if dist < 80
    thrust(speed: 8, angle: chase_angle)
    shield(8) if energy > 15  # Max shields for impact
  elsif dist < 150
    thrust(speed: 7, angle: chase_angle)
    shield(6) if energy > 20
  else
    thrust(speed: 5, angle: chase_angle)
    shield(3) if energy > 30
  end
end
```

**Why ramming works**:
- Large mass (1.56) = 18 collision damage at max speed
- 120 HP survives the mutual damage
- Shields absorb return damage
- No aiming required - just collide

**Tradeoff**: Dominates 1v1 but struggles in multi-bot (big target gets focused).

| Format | Win Rate |
|--------|----------|
| 1v1 | 29% (best) |
| 5-way | 0% (worst) |

### Hunter (Pursuit Predator)

**Strategy**: Small size for mobility, patrol until target found, chase relentlessly, probe for health, finish weak targets.

**Key behaviors**:
1. Patrol with pulse detection (300 radius, every 3 ticks)
2. Chase with scan tracking (70° arc, velocity data)
3. Intercept moving targets (predict where they'll be)
4. Probe for health every 8 ticks
5. "Finish them" mode when target < 40 HP (max fire power)
6. Reactive dodge on hit (perpendicular to bullet direction)

```ruby
# Direct pursuit - no strafing
move_angle = if target_speed < 2
               angle_to(base_x, base_y)      # Direct for stationary
             elsif dist > 180
               calculate_intercept_angle     # Intercept when far
             else
               angle_to(base_x, base_y)      # Direct to close and kill
             end
```

**Design decision - No circular strafing**: Testing showed direct pursuit outperforms strafing:
- Strafing: 76 wins in 1v1 test
- Direct: 91 wins in 1v1 test

Strafing hurts because turret rotation is limited (15°/tick) and bullets are fast (18/tick). DPS beats evasion.

**Design decision - Chase speed 7 not 8+**: Lower speed conserves energy for shields and firing. Speed 6-7 optimal, 9+ hurts performance.

### Patroller (Perimeter Patrol)

**Strategy**: Small size, patrol arena perimeter clockwise, reverse at corners, scan inward for targets.

**Key behaviors**:
1. Move to nearest wall at spawn
2. Patrol perimeter with oscillating speed (4-6)
3. Reverse direction at corners after probing
4. Turret biased inward toward center
5. Track targets with probe, lead calculation for shooting

```ruby
def patrol_perimeter
  if near_corner
    probe_next_corner
    @clockwise = !@clockwise  # Reverse at corners
  end

  # Speed oscillation for unpredictability
  @speed_phase = (@speed_phase + 1) % 20
  current_speed = @speed_phase < 10 ? SPEED_SLOW : SPEED_FAST

  update_patrol_angle
  thrust(speed: current_speed, angle: @patrol_angle)
  scan_and_engage
end
```

**Why perimeter patrol**: Keeps back to wall (limits attack angles), covers entire arena over time, unpredictable movement pattern.

**Weakness**: Patrol path is predictable, walks into corner campers.

---

## Balance Analysis & Design Tradeoffs

### Energy Economy

Energy is the core resource. Every action costs energy, and regeneration is fixed by size. Winning strategies maximize damage output per energy spent.

**Energy budget per tick (by size)**:
| Size | Regen | Max Sustainable Actions |
|------|-------|------------------------|
| Small | 8 | ~8 energy of actions/tick |
| Medium | 10 | ~10 energy of actions/tick |
| Large | 12 | ~12 energy of actions/tick |

**Action cost comparison**:
| Action | Cost | Damage/Utility |
|--------|------|----------------|
| probe() | 4-7 | Confirms target |
| fire(10) | 10 | 15 damage |
| thrust(speed: 5) | 6-17 (by mass) | Movement |
| shield(5) | 5 | 5 shield (decays 12%/tick) |
| scan(60°, 300) | 9 | Area awareness |

**Key insight**: Stationary bots win because movement is expensive. A small bot moving at speed 5 spends ~6 energy/tick on thrust alone, leaving only 2 for everything else. A stationary bot has all 8-12 energy for offense.

### Mobility vs Firepower Tradeoff

Testing revealed that **stationary > mobile** in most scenarios:

| Strategy | Win Rate | Why |
|----------|----------|-----|
| Corner camp (Coroner) | 43.8% | All energy to offense, limited approach angles |
| Stationary spin (Spinner) | 23.6% | All energy to offense |
| Mobile pursuit (Hunter) | 8.4% | Energy split between movement and combat |
| Mobile patrol (Patroller) | 7.5% | Energy split, predictable path |

**Exception**: Crusher's ramming (16.4%) works because collision damage doesn't cost energy - it's "free" damage from momentum.

### Sensing System Tradeoffs

Three sensing options with different cost/benefit:

| Method | Cost | Coverage | Detail | Best For |
|--------|------|----------|--------|----------|
| probe() | 4-7 | Single target | High (health, energy) | Tracking known target |
| scan() | 5-16 | Arc (configurable) | Medium (position, velocity) | Finding targets |
| pulse() | 3-5 | 360° | Low (position only) | Quick awareness check |

**Design decision**: Sensing has 1-tick delay. You call `probe()` this tick, get results next tick. This prevents perfect reaction and rewards prediction.

**Optimal sensing pattern**:
1. `pulse()` to detect presence (cheap, 360°)
2. `scan()` to get velocity for lead calculation
3. `probe()` for health to prioritize weak targets

### Shield System Analysis

Shields use proportional decay (12%/tick), making high shields expensive:

| Shield Level | Decay/tick | Cost to Maintain |
|--------------|------------|------------------|
| 20 | 2.4 | 2.4 energy/tick |
| 50 | 6 | 6 energy/tick |
| 100 | 12 | 12 energy/tick (all large bot regen) |

**Implication**: Sustained high shields are impossible while fighting. Shields are for burst protection:

```ruby
# Good: Burst shield when hit
def on_hit(damage, direction)
  shield(15) if energy > 30  # Spike to survive follow-up
end

# Bad: Constant high shield
def tick
  shield(12) if shield_level < 100  # Drains all energy, can't fight
end
```

### Size Selection Guide

| Size | Best For | Worst For |
|------|----------|-----------|
| Small | Mobile hunters, evasion | Ramming, tanking |
| Medium | Balanced, turret-based | Extreme strategies |
| Large | Ramming, sustained fire | Mobility, dodging |

**Small (80 HP, 0.56 mass)**:
- 2.8x harder to hit by area
- Cheapest thrust (0.56x cost)
- Dies fast if caught

**Large (120 HP, 1.56 mass)**:
- 18 collision damage at max speed
- Highest sustained DPS (12 regen)
- Easy target, expensive to move

### Combat Insights from Testing

**1. Turret rotation matters**
- Max rotation: 15°/tick
- Optimal spinner speed: 7°/tick (balances coverage vs hits-per-pass)
- Fast rotation (15+°) can skip targets between ticks

**2. Chase speed optimization**
- Speed 6-7 optimal for pursuit
- Speed 8+ burns too much energy
- Arrive with energy reserves, not empty

**3. Strafing doesn't help**
- Direct pursuit: 91 wins (1v1 test)
- Circle strafe: 76 wins
- Reason: Turret lag + fast bullets = missed shots while moving sideways

**4. Lead calculation is essential**
- Bullets travel 18 units/tick
- Moving targets need prediction: `target_x + velocity_x * (distance / 18)`
- Bots without lead calculation lose to mobile opponents

**5. Multi-bot dynamics**
- Aggressive bots get focused and die early
- Defensive/camping scales with chaos
- Crusher: 29% in 1v1, 0% in 5-way
- Coroner: 30% in 1v1, 68% in 5-way

### Counter Strategies

| Bot | Countered By | Counter Strategy |
|-----|--------------|------------------|
| Spinner | Coroner | Out-range with corner position |
| Coroner | Crusher | Ram before sniper can kill |
| Crusher | Coroner | Kite and snipe during approach |
| Hunter | Spinner | Stand still, let Hunter come to you |
| Patroller | Coroner | Patrol walks into corner ambush |

The meta forms a partial rock-paper-scissors with Coroner dominant due to scaling with chaos.

---

## Open Questions / Future Features
- Team battles (2v2, 3v3)?
- Customizable rubot appearance/colors?
- Achievement system?
- Spectator chat during live matches?
- API for external bot submission (GitHub integration)?

---

## Dependencies

```ruby
# Gemfile
source 'https://rubygems.org'

gemspec

group :development, :test do
  gem 'minitest', '~> 5.20'
  gem 'rake'
end
```

Minimal dependencies - the engine should be self-contained with no external runtime dependencies.
