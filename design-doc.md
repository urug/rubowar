# Rubowar: Ruby Robot Battle Arena

## Overview
A competitive programming game where Ruby club members write Ruby classes to control robots ("Rubots") that battle in an arena. The engine is a standalone Ruby gem with a pluggable renderer interface - bring your own visualization (terminal, web, desktop app, etc.).

---

## Core Design Decisions

### Robot API
```ruby
class Destructo
  include Rubot

  def tick
    # Access state via methods: energy, health, x, y, turret_angle, body_angle, etc.
    # Call action methods directly: move, fire, turn_turret, look, radar
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

**Error Handling**: If a robot's code crashes or times out, it takes **10 damage** and skips that tick. This encourages robust code without instant disqualification.

### Rubot Module - Complete API

#### Robot Size (chosen at class definition)

```ruby
class MyRobot
  include Rubot
  size :medium  # :small, :medium, or :large
end
```

| Size | Radius | Energy Regen | Collision Bonus |
|------|--------|--------------|-----------------|
| `:small` | 15 units | +8/tick | Takes +3 damage from larger robots |
| `:medium` | 20 units | +10/tick | Standard collision damage |
| `:large` | 25 units | +12/tick | Deals +3 damage to smaller robots |

**Collision damage formula**: Base 5 + size bonus. Small vs Large = Small takes 8, Large takes 2.

#### State Accessors (read-only)
| Method | Type | Description |
|--------|------|-------------|
| `x`, `y` | Float | Current position in arena |
| `velocity_x`, `velocity_y` | Float | Current velocity vector |
| `speed` | Float | Magnitude of velocity (convenience) |
| `body_angle` | Float | Direction robot body faces (0-360°) |
| `turret_angle` | Float | Direction turret points (0-360°, absolute) |
| `health` | Integer | Current HP (starts at 100) |
| `energy` | Integer | Current energy (max 100, regen varies by size) |
| `shield_level` | Integer | Current shield level (0 = no shield, degrades 2/tick, max 50) |
| `arena_width`, `arena_height` | Integer | Arena dimensions |
| `friction` | Float | Arena friction coefficient (default 0.95) |
| `tick_number` | Integer | Current game tick |
| `damage_dealt` | Integer | Total damage dealt this match |
| `damage_taken` | Integer | Total damage received this match |
| `energons` | Array | All energon positions `[{x:, y:}]` (always visible, free) |
| `size` | Symbol | Robot's size (`:small`, `:medium`, `:large`) |

#### Action Methods
| Method | Cost | Description |
|--------|------|-------------|
| `thrust(energy)` | energy spent | Add velocity in body direction. **velocity = √energy × 1.5** (physics-based). |
| `turn(degrees)` | \|degrees\|/10 energy | Rotate body only. Negative = left, positive = right. |
| `turret(degrees)` | \|degrees\|/30 energy | Rotate turret only. Cheaper than body turn. |
| `fire(energy)` | energy spent | Fire projectile. Damage = **1.5 × energy**. Any amount up to current energy. All travel 15 u/tick. |
| `shield(energy)` | energy spent | Pump energy into shield. Shield strength = energy invested. Degrades 2/tick. |
| `look(energy)` | 1-5 energy | Line in turret direction. More energy = more detail (see below). |
| `scan(width)` | width energy | Cone of `width` degrees. Returns `[{distance:, angle:}]` for robots in cone. |
| `pulse(radius)` | radius²/10 energy | Circle around self. Returns `[{distance:, angle:}]` for robots in radius. (least detail) |

**Turn cost examples**: `turn(90)` costs 9 energy, `turn(-45)` costs 4.5 energy, `turret(90)` costs 3 energy

#### Sensing System

**`look(energy)`** - Variable detail line scan (size always free)

| Cost | Returns |
|------|---------|
| 1 | position + size |
| 2 | + velocity |
| 3 | + shield_level |
| 4 | + health |
| 5 | + energy |

```ruby
look(1) → {x: 400, y: 300, size: :large}
look(3) → {x: 400, y: 300, size: :large, velocity_x: 5, velocity_y: -2, shield_level: 20}
look(5) → {x: 400, y: 300, size: :large, velocity_x: 5, velocity_y: -2, shield_level: 20, health: 75, energy: 50}
look(n) → nil  # nothing in line of sight
```

**`scan(width)`** - Cone scan (width degrees, costs width energy)
- Returns: position + body_angle + shield_level + size
- Also detects bullets: position + velocity

**`pulse(radius)`** - Circle scan (costs radius²/10 energy)
- Returns: position + size only
- Also detects bullets: position only

```ruby
scan(30) → {
  robots: [{x: 400, y: 300, body_angle: 45, shield_level: 10, size: :small}],
  bullets: [{x: 350, y: 280, velocity_x: 10, velocity_y: 5}]
}

pulse(10) → {
  robots: [{x: 400, y: 300, size: :medium}],
  bullets: [{x: 350, y: 280}]
}
```

**Bullet awareness**: scan and pulse detect incoming bullets!

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
  # Maintain shield at ~20 level
  shield(5) if shield_level < 20

  # Or burst shield when under attack
  shield(30) if under_fire?
end
```

**Strategy**: Constant small investments (2-3 energy/tick) maintain a buffer. Burst shielding when you detect incoming bullets via `scan`.

#### Physics
- **Movement**: `thrust(energy)` adds velocity (√energy × 1.5). Friction slows robots each tick (default 0.95×, configurable per tournament).
- **Projectiles**: Travel at **18 units/tick** (slightly slower than max robot speed). Can hit anyone including the shooter. Disappear on contact or after leaving arena.
- **Wall collision**: **10 damage** + bounce. Walls hurt! Discourages reckless speed.
- **Robot collision**: **5 damage** to both robots + push apart. Less than walls.
- **Max speed**: Capped at 20 units/tick to prevent wall-slamming exploits.

#### Callbacks
```ruby
def on_hit(damage, direction)    # Called when taking damage from projectile
def on_spawn                     # Called at match start
def on_death                     # Called when health reaches 0
def on_wall                      # Called on wall collision (10 damage)
def on_collision(robot)          # Called on robot collision (5 damage), receives other robot info
def on_energon(amount)           # Called when collecting energon (20-80 energy)
```

### Arena

**Dimensions**: Variable (default 800×600 units)
- Configurable per match/tournament
- Robots access via `arena_width` and `arena_height` accessors

**Coordinate System**:
- Origin (0,0) at **bottom-left** corner
- X increases rightward (0 to arena_width)
- Y increases upward (0 to arena_height)
- **0° = Right (East)**, 90° = Up, 180° = Left, 270° = Down

**Spawning**:
- **Random positions** at match start
- Minimum distance from walls (50 units)
- Minimum distance between robots (100 units)
- Random starting angle

**Players**: 2-4 robots per match (1v1, 1v1v1, 1v1v1v1, or 2v2)

**Walls**: Collision causes 10 damage + bounce

### Energons

Simple energy power-up system. No healing - damage is permanent.

| Type | Effect | Spawn Rate |
|------|--------|------------|
| Energon | +20 to +80 energy (random) | Every ~150 ticks |

**Energon mechanics:**
- Max 2 energons on field at once
- Spawn at random positions (not too close to robots or walls)
- Collect by touching (radius ~15 units)
- Energy is capped at 100 even with energons
- `on_energon(amount)` callback fires when collected

**Detection:** Energons are **always visible** via the `energons` accessor (free, no energy cost). Returns `[{x:, y:}]` for all energons on the field. The actual energy amount (20-80) is hidden until collected - adds risk/reward decisions.

### Victory Condition
- Last robot standing wins
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
│   │   ├── match.rb           # Runs a single match
│   │   ├── robot_runner.rb    # Sandboxed execution of robot code
│   │   ├── bullet.rb          # Projectile tracking
│   │   ├── energon.rb         # Energy power-up
│   │   └── events.rb          # Event types for renderers
│   └── rubowar.rb
├── test/
├── robots/                    # Example robots for learning
│   ├── spinner.rb
│   ├── tracker.rb
│   └── wall_hugger.rb
├── bin/
│   └── rubowar                # CLI to run matches
├── Gemfile
├── rubowar.gemspec
└── README.md
```

### Renderer Interface

The engine is renderer-agnostic. It emits events that any renderer can consume:

```ruby
match = Rubowar::Match.new(robots: [Spinner, Tracker], width: 800, height: 600)

# Option 1: Block-based (for real-time renderers)
match.on(:tick) { |state| render_frame(state) }
match.on(:hit) { |event| play_sound(:hit) }
match.on(:death) { |event| show_explosion(event) }
match.run

# Option 2: Collect all events (for replays)
events = match.run  # Returns array of all events
save_replay(events)

# Option 3: Simple terminal output (built-in)
match.run(renderer: Rubowar::Renderers::Terminal)
```

**Event Types**:
- `:tick` - Full game state each tick
- `:fire` - Robot fired a projectile
- `:hit` - Projectile hit a robot
- `:death` - Robot destroyed
- `:wall_collision` - Robot hit wall
- `:robot_collision` - Robots collided
- `:energon_spawn` - Energon appeared
- `:energon_collect` - Robot collected energon
- `:match_end` - Match concluded with winner

### Key Components

#### 1. Rubot Module (`lib/rubowar/rubot.rb`)
- Included by participant classes
- Registers the class with the game engine
- Provides helper methods: `move`, `fire`, `look`, `radar`, `turn_body`, `turn_turret`
- Actions are queued and returned from `tick`

#### 2. Arena (`lib/rubowar/arena.rb`)
- Manages game state: robot positions, velocities, health, energy
- Handles physics: movement, projectile travel, collisions
- Spawns and manages energons
- Emits events for renderers

#### 3. Match (`lib/rubowar/match.rb`)
- Loads robot classes (sandboxed)
- Runs game loop: call each robot's `tick`, process actions, update state
- Emits events via callbacks (renderer-agnostic)
- Determines winner

#### 4. Robot Runner (`lib/rubowar/robot_runner.rb`)
- **Sandboxing**: Runs robot code with restrictions
  - No file I/O, network, system calls
  - Time limit per tick (e.g., 10ms) to prevent infinite loops
  - Memory limits
- Process isolation with JSON communication

#### 5. Terminal Renderer (`lib/rubowar/renderers/terminal.rb`)
- Built-in simple renderer for testing
- ASCII visualization of arena state
- Useful for development and debugging

---

## Implementation Phases

### Phase 1: Core Engine (MVP)
1. Project structure with gemspec
2. `Rubot` module with basic API (state accessors, action methods)
3. `Arena` with physics (movement, friction, collision)
4. `Match` runner with event emission
5. Basic actions: thrust, turn, turret, fire, look
6. Terminal renderer for testing
7. 2-3 example robots

### Phase 2: Full Sensing & Combat
1. Complete sensing system (look, scan, pulse)
2. Shield system
3. All callbacks (on_hit, on_wall, on_collision, etc.)
4. Robot sizes with tradeoffs

### Phase 3: Energons & Polish
1. Energon spawning and collection
2. CLI tool (`bin/rubowar`) for running matches
3. Match replay recording (event log)

### Phase 4: Sandboxing & Safety
1. Process isolation for robot execution
2. Time limits per tick
3. Dangerous method removal

---

## Technical Decisions

### Sandboxing (Process Isolation)

Since all code runs server-side, we need proper sandboxing to prevent cheating and abuse.

**Architecture:**
```
Main Process (Rails)              Robot Process (Sandboxed)
┌─────────────────────┐          ┌─────────────────────┐
│ Match Runner        │   JSON   │ Robot Code          │
│ - Arena physics     │ ◄──────► │ - tick() execution  │
│ - State management  │   pipe   │ - Isolated Ruby     │
│ - WebSocket stream  │          │ - No game access    │
└─────────────────────┘          └─────────────────────┘
```

**How it works:**
1. Match runner spawns a subprocess for each robot
2. Sends state as JSON: `{x:, y:, energy:, health:, energons:, ...}`
3. Robot subprocess executes `tick()`, returns actions as JSON: `[{action: "thrust", power: 3}, ...]`
4. Match runner validates actions, applies physics, repeats
5. Subprocess is killed if it times out (10ms limit per tick)

**Security layers:**
- **Process isolation**: Robot can't access Arena/Match (different process)
- **No dangerous methods**: Subprocess loads robot in clean environment, removes `File`, `IO`, `Net::HTTP`, `ObjectSpace`, `Kernel.system`, `eval`, `require`, etc.
- **Timeout enforcement**: Process-level kill if tick exceeds time limit
- **Resource limits**: ulimit on memory, CPU
- **Optional Docker**: For extra isolation, run subprocess in container

**Implementation**: Use Ruby's `Open3.popen3` or a gem like `childprocess` for subprocess management.

---

## Example Robots

### Basic: Spinner
```ruby
class Spinner
  include Rubot

  def tick
    turret(10)                 # Constantly rotate turret (cheap)
    fire(1) if look            # Fire when we see someone
    thrust(1) if speed < 3     # Keep moving slowly
  end
end
```

### Intermediate: Tracker
```ruby
class Tracker
  include Rubot

  def tick
    if energy > 30
      # Radar scan for enemies
      enemies = radar(5)  # Costs 25 energy

      if enemies.any?
        target = enemies.min_by { |e| e[:distance] }

        # Aim and fire
        angle_diff = normalize_angle(target[:angle] - turret_angle)
        turret(angle_diff)
        fire(3) if angle_diff.abs < 10 && energy > 40

        # Strafe perpendicular to target
        turn(target[:angle] + 90 - body_angle)
        thrust(3)
      else
        search_pattern
      end
    else
      # Low energy - conserve, just look
      turret(15)
      fire(1) if look
    end
  end

  def on_hit(damage, direction)
    shield(true) if energy > 20  # Activate shield when hit
    turn(direction + 90)         # Turn perpendicular
    thrust(5)                    # Burst away
  end

  private

  def search_pattern
    turn(5)
    thrust(2) if speed < 5
  end

  def normalize_angle(angle)
    angle = angle % 360
    angle -= 360 if angle > 180
    angle
  end
end
```

### Advanced: Wall Hugger
```ruby
class WallHugger
  include Rubot

  def on_spawn
    @patrol_direction = 1
  end

  def tick
    # Stay near walls for protection
    near_wall = x < 50 || x > arena_width - 50 ||
                y < 50 || y > arena_height - 50

    if near_wall
      patrol_along_wall
    else
      move_to_nearest_wall
    end

    # Always be scanning and shooting
    scan_and_fire
  end

  def on_collision(what)
    @patrol_direction *= -1 if what == :wall
  end

  private

  def patrol_along_wall
    # Move parallel to nearest wall
    turn(90 * @patrol_direction)
    thrust(3)
  end

  def move_to_nearest_wall
    # Find nearest wall and head toward it
    distances = {
      0 => arena_width - x,   # right wall
      90 => arena_height - y, # top wall
      180 => x,               # left wall
      270 => y                # bottom wall
    }
    nearest_wall_angle = distances.min_by { |_, d| d }.first
    turn(nearest_wall_angle - body_angle)
    thrust(4)
  end

  def scan_and_fire
    turret(20)  # Sweep turret
    distance = look
    if distance && distance < 200
      fire(4)  # Heavy shot at close range
    elsif distance
      fire(2)  # Light shot at distance
    end
  end
end
```

---

## Open Questions / Future Features
- Team battles (2v2, 3v3)?
- Customizable robot appearance/colors?
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

---

## Next Steps (Phase 1)
1. Initialize gem structure (gemspec, lib/, test/, robots/)
2. Implement `Rubot` module with state accessors and action methods
3. Implement `Arena` with physics (movement, friction, wall collision)
4. Implement `Match` runner with event emission
5. Implement `Bullet` for projectile tracking
6. Create terminal renderer
7. Create example robots (Spinner, Tracker)
8. Add tests for core functionality
