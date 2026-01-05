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
    # Call action methods directly: thrust, fire, turret, look, shield
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
| `shield_level` | Integer | Current shield level (0 = no shield, degrades 2/tick, max 50) |
| `arena_width`, `arena_height` | Integer | Arena dimensions |
| `friction` | Float | Arena friction coefficient (default 0.95) |
| `tick_number` | Integer | Current game tick |
| `damage_dealt` | Integer | Total damage dealt this match |
| `damage_taken` | Integer | Total damage received this match |
| `energons` | Array | All energon positions `[{x:, y:}]` (always visible, free) |
| `size` | Symbol | Rubot's size (`:small`, `:medium`, `:large`) |

#### Action Methods
| Method | Cost | Description |
|--------|------|-------------|
| `thrust(speed:, angle:)` | (speed/1.5)^2 x mass x direction | Add velocity in world direction |
| `turret(degrees)` | \|degrees\|/30 energy | Rotate turret. Negative = left, positive = right. |
| `fire(energy)` | energy spent | Fire projectile. Damage = **1.5 x energy**. Bullets travel 18 u/tick. |
| `shield(energy)` | energy spent | Pump energy into shield. Degrades 2/tick. Max 50. |
| `look(*attributes)` | 1 + attribute costs | Line in turret direction. Returns target info or nil. |

**Thrust mechanics:**
- `angle` is in world coordinates (0° = East, 90° = North)
- Cost formula: `(speed / 1.5)^2 x mass x direction_multiplier`
- Direction multiplier: 1.0 (same direction as current velocity) to 2.0 (opposite direction)
- If insufficient energy for full thrust, you get partial thrust and energy drains to zero

**Turret cost examples**: `turret(90)` costs 3 energy, `turret(-45)` costs 1.5 energy

#### Sensing System

**`look(*attributes)`** - Line scan in turret direction

| Attribute | Cost | Returns |
|-----------|------|---------|
| (base) | 1 | x, y |
| `:size` | +1 | size (:small/:medium/:large) |
| `:velocity` | +2 | velocity_x, velocity_y |
| `:shield` | +2 | shield_level |
| `:health` | +3 | health |
| `:energy` | +3 | energy |

```ruby
look                    # 1 energy  -> {x: 400, y: 300}
look(:size)             # 2 energy  -> {x: 400, y: 300, size: :large}
look(:size, :velocity)  # 4 energy  -> {x: 400, y: 300, size: :large, velocity_x: 5, velocity_y: -2}
look(:size, :velocity, :shield, :health, :energy)  # 12 energy -> everything
look(...)               # nil if nothing in line of sight
```

**Important:** `look()` returns the result from the PREVIOUS tick's look. Since actions are processed after tick(), the current look result won't be available until the next tick.

#### Shield System

Shields absorb damage before health. They require continuous energy investment to maintain.

**Mechanics**:
- `shield(energy)` - Add energy to shield strength
- Shield degrades **2 points per tick** naturally
- Damage hits shield first, then health when shield = 0
- Shield absorbs damage 1:1 (10 damage removes 10 shield)
- Max shield strength: 50

**Example**:
```ruby
def tick
  # Maintain shield at ~20 level (costs 2 energy/tick to counter degradation)
  shield(4) if shield_level < 20

  # Or burst shield when under attack
  shield(30) if under_fire?
end
```

**Strategy**: Shields are tactical (absorb burst damage) rather than strategic. To maintain 20 shield, you need 2 energy/tick just to counter degradation.

#### Physics

- **Movement**: `thrust(speed:, angle:)` adds velocity in world direction. Cost = (speed/1.5)^2 x mass x direction_multiplier.
- **Friction**: Velocity *= 0.95 each tick (configurable per tournament).
- **Max speed**: Capped at 20 units/tick.
- **Projectiles**: Travel at **18 units/tick** (slightly slower than max rubot speed). Spawn at edge of rubot (position + rubot radius + bullet radius). Can hit anyone including the shooter.
- **Wall collision**: `2 + speed x 0.75` damage + bounce. At max speed: 17 damage.
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

Simple energy power-up system. No healing - damage is permanent.

| Type | Effect | Spawn Rate |
|------|--------|------------|
| Energon | +20 to +80 energy (random) | Every ~150 ticks |

**Energon mechanics:**
- Max 2 energons on field at once
- Spawn at random positions (not too close to rubots or walls)
- Collect by touching (radius ~15 units)
- Energy is capped at 100 even with energons
- `on_energon(amount)` callback fires when collected

**Detection:** Energons are **always visible** via the `energons` accessor (free, no energy cost). Returns `[{x:, y:}]` for all energons on the field. The actual energy amount (20-80) is hidden until collected - adds risk/reward decisions.

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
│   │   └── renderers/
│   │       └── terminal.rb    # ASCII visualization
│   └── rubowar.rb
├── test/
├── robots/                    # Example rubots for learning
│   ├── spinner.rb
│   └── tracker.rb
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
- Provides action methods: `thrust`, `turret`, `fire`, `shield`, `look`
- Actions are queued and processed after tick returns

#### 2. Arena (`lib/rubowar/arena.rb`)
- Manages physics: movement, friction, collisions
- Processes actions: thrust, turret, fire, shield, look
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

## Example Rubots

### Basic: Spinner
```ruby
class Spinner
  include Rubowar::Rubot
  size :small

  def tick
    turret(10)                           # Constantly rotate turret (cheap)
    fire(5) if look                      # Fire when we see someone
    thrust(speed: 2, angle: 0) if speed < 3  # Drift slowly
  end
end
```

### Intermediate: Tracker
```ruby
class Tracker
  include Rubowar::Rubot
  size :small

  def on_spawn
    @heading = rand(360)
    @turn_direction = 1
  end

  def tick
    avoid_walls
    patrol
    look_and_fire
  end

  def on_hit(_damage, direction)
    # Boost perpendicular to incoming fire
    thrust(speed: 5, angle: direction + 90)
  end

  def on_wall
    @turn_direction *= -1
    @heading = (@heading + 180) % 360
  end

  private

  def avoid_walls
    near_wall = x < 80 || x > arena_width - 80 ||
                y < 80 || y > arena_height - 80
    @heading = (@heading + 45 * @turn_direction) % 360 if near_wall
  end

  def patrol
    @heading = (@heading + 5 * @turn_direction) % 360 if rand < 0.05
    thrust(speed: 3, angle: @heading) if speed < 4
  end

  def look_and_fire
    target = look(:velocity)

    if target
      fire(8) if energy > 30
      shield(5) if energy > 50 && shield_level < 20
    else
      turret(8)
    end
  end
end
```

---

## Open Questions / Future Features
- Team battles (2v2, 3v3)?
- Customizable rubot appearance/colors?
- Achievement system?
- Spectator chat during live matches?
- API for external bot submission (GitHub integration)?
- Implement scan() and pulse() sensing methods?

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
