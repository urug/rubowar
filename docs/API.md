# Rubot API Reference

Complete API reference for writing rubots. For a hands-on introduction, see the [Tutorial](TUTORIAL.md).

## Quick Reference

```ruby
class MyRubot
  include Rubowar::Rubot
  size :medium  # :small, :medium, or :large

  def on_spawn
    # Called once when battle starts
  end

  def act
    # Called every chronon - your main logic
    thrust(speed: 5, angle: 90)
    rotate_turret(15)
    fire(10)
  end
end
```

---

## State Accessors (read-only)

| Method | Description |
|--------|-------------|
| `id` | Unique identifier (e.g., "rbot-a1b2c3d4") |
| `name` | Display name |
| `x`, `y` | Position in arena |
| `velocity_x`, `velocity_y` | Current velocity |
| `speed` | Velocity magnitude |
| `turret_angle` | Turret direction (0-360, world coordinates) |
| `health` | Current HP (varies by size) |
| `max_health` | Maximum HP (varies by size) |
| `energy` | Current energy (max 100) |
| `shield_level` | Shield strength (0 to max_health, decays 12%/chronon) |
| `arena_width`, `arena_height` | Arena dimensions |
| `friction` | Arena friction (default 0.92) |
| `chronon` | Current game tick |
| `damage_dealt`, `damage_taken` | Match stats |
| `energons` | All energon positions `[{x:, y:}]` (free) |
| `size` | Rubot size (:small, :medium, :large) |
| `live_rubot_count` | Number of rubots still alive |
| `energon_spawn_interval` | Ticks between energon spawns (default 50) |
| `energon_growth_rate` | Energy growth per chronon (default 1.0) |

---

## Actions

| Method | Cost | Effect |
|--------|------|--------|
| `thrust(speed:, angle:)` | (speed/1.5)^2 x mass x direction | Add velocity in world direction |
| `rotate_turret(degrees)` | ceil(\|degrees\|/24) | Rotate turret |
| `fire(energy)` | energy | Damage = 1.5 x energy, bullet speed 18 |
| `raise_shields(energy)` | energy | Add to shield (max = HP cap, decays 12%/chronon) |

### Action Processing Order

**Actions are processed in phases, not in the order you call them.** This ensures fairness (no spawn-order advantage).

```
Phase 1: SENSE   → All probe(), scan(), pulse() for all rubots
Phase 2: MOVE    → All thrust(), rotate_turret() for all rubots → physics
Phase 3: COMBAT  → All fire(), raise_shields() for all rubots → bullets
```

**Energy is deducted in phase order:**

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

**Bullets spawn from your post-movement position.** You move, then shoot from where you are.

### Thrust Mechanics

- `angle` is in world coordinates (0 = east, 90 = north)
- Cost increases with mass (larger rubots cost more to move)
- Changing direction costs more (1.0x same direction, 2.0x opposite)
- If you can't afford full thrust, you get partial thrust

**Estimating thrust cost:**

```ruby
def act
  escape_angle = angle_to(target_x: 320, target_y: 320) + 180
  cost = thrust_cost(thrust_speed: 6, angle: escape_angle)

  if cost <= energy - 15  # Reserve 15 for combat
    thrust(speed: 6, angle: escape_angle)
  else
    thrust(speed: 3, angle: velocity_angle || 0)  # Cheaper option
  end
end
```

---

## Sensing

| Method | Cost | Returns |
|--------|------|---------|
| `probe(*attributes)` | sum of attribute costs | Line scan in turret direction |
| `scan(angle:, distance:, velocity:, owner:)` | 3 + area cost [+2] [+1] | Arc scan for all targets |
| `pulse(distance:, owner:)` | 2 + ceil(distance/75) [+1] | 360° radar ping |
| `detect` | 2 | Counter-intelligence |

### probe() - Single target, detailed info

Cost is the sum of requested attributes:

| Attribute | Cost | Returns |
|-----------|------|---------|
| `:size` | 1 | size category |
| `:position` | 4 | x, y coordinates |
| `:velocity` | 3 | velocity_x, velocity_y |
| `:turret_angle` | 2 | turret angle in degrees |
| `:shield` | 2 | shield_level |
| `:health` | 3 | current health |
| `:energy` | 3 | current energy |

```ruby
probe                        # 1 energy  -> defaults to :size
probe(:position)             # 4 energy  -> x, y
probe(:size, :position)      # 5 energy  -> size, x, y
probe(:position, :velocity)  # 7 energy  -> x, y, velocity_x, velocity_y

# Check results next chronon:
probe_echo.found?            # true if target detected
probe_echo.x                 # position (if requested)
probe_echo.velocity_x        # velocity (if requested)
```

### scan() - Multiple targets, position/velocity only

Cost: `3 + ceil(angle/20) + ceil(distance/100)` [+2 for velocity] [+1 for owner]

```ruby
scan(angle: 20, distance: 100)                 # 5 energy
scan(angle: 20, distance: 100, velocity: true) # 7 energy
scan(angle: 90, distance: 300)                 # 11 energy

# Check results next chronon:
scan_echo.any_rubots?
scan_echo.rubots
scan_echo.closest_rubot(to_x: x, to_y: y)
```

### pulse() - Quick 360° awareness

Cost: `2 + ceil(distance/75)` [+1 for owner]

```ruby
pulse(distance: 75)               # 3 energy
pulse(distance: 100)              # 4 energy
pulse(distance: 100, owner: true) # 5 energy

# Check results next chronon:
pulse_echo.any_rubots?
pulse_echo.closest_rubot(to_x: x, to_y: y)
```

### detect() - Counter-intelligence

Cost: 2 energy

```ruby
detect  # 2 energy

# Check results next chronon:
detect_intel.targeted?  # true if sensed by anyone
detect_intel.probed     # times probed this chronon
```

### Sensing Delay

**All sensing results are delayed by one chronon.** Like a radar ping, you send the signal and receive the echo on the next chronon.

```
Chronon N:
  1. Your act() reads probe_echo → results from Chronon N-1
  2. You call probe(:position)   → queued for execution
  3. Sense phase executes        → result stored

Chronon N+1:
  1. Your act() reads probe_echo → NOW contains Chronon N's results
```

![Sensing Delay Diagram](sensing-delay.svg)

**Pattern for using sensing:**

```ruby
def act
  # FIRST: Read results from PREVIOUS chronon
  if probe_echo.found?
    target_angle = angle_to(target_x: probe_echo.x, target_y: probe_echo.y)
    turret_diff = normalize_angle(target_angle - turret_angle)
    rotate_turret(turret_diff.clamp(-20, 20))
    fire(10) if turret_diff.abs < 15
  end

  # THEN: Queue sensing for NEXT chronon
  probe(:position, :velocity)
end
```

### Sensing Result Objects

Results are structured objects with helper methods. They're never nil:

```ruby
# ProbeEcho - single target
probe_echo.found?       # Was a target detected?
probe_echo.empty?       # No target found?
probe_echo.x            # Position (if requested)
probe_echo[:x]          # Hash-style access works too

# ScanEcho / PulseEcho - multiple targets
scan_echo.empty?
scan_echo.rubots        # Filter to only rubots
scan_echo.bullets       # Filter to only bullets
scan_echo.any_rubots?
scan_echo.closest_rubot(to_x: x, to_y: y)
scan_echo.each { |t| ... }  # Enumerable

# DetectIntel - counter-intelligence
detect_intel.targeted?  # Was I sensed?
detect_intel.probed     # How many times probed
detect_intel.scanned    # How many times scanned
detect_intel.pulsed     # How many times pulsed
```

---

## Callbacks

All callbacks use keyword arguments:

```ruby
def on_spawn
  # Called once when battle starts
end

def on_death
  # Called when health reaches 0
end

def on_wall
  # Called on wall collision
end

def on_hit(damage:, direction:)
  # damage: Integer - damage taken
  # direction: Float - angle shot came from (degrees)
end

def on_collision(other:)
  # other: RubotState - snapshot of the other rubot
  # Contains: id, name, x, y, velocity_x, velocity_y, speed,
  #           turret_angle, health, max_health, energy, shield_level,
  #           damage_dealt, damage_taken, size
end

def on_energon(amount:)
  # amount: Integer - energy collected
end
```

---

## Rubot Sizes

| Size | Radius | HP | Energy Regen | Mass |
|------|--------|-----|--------------|------|
| `:small` | 6 | 50 | +7/chronon | 0.36 |
| `:medium` | 10 | 90 | +16/chronon | 1.0 |
| `:large` | 14 | 120 | +18/chronon | 1.96 |

**Tradeoffs:**
- **Small**: Harder to hit, cheapest thrust, but least HP
- **Medium**: Balanced baseline
- **Large**: Most HP and regen, but expensive to move and easier to hit

---

## Helper Methods

### Angle Calculations

```ruby
# Angle from your position to a target
angle_to(target_x:, target_y:)  # Returns 0-360

# Normalize angle to -180..180 range
normalize_angle(angle)

# Your current movement direction (nil if stationary)
velocity_angle
```

### Distance Calculations

```ruby
# Distance from your position to a point
distance_to(target_x:, target_y:)
```

### Wall Detection

```ruby
# Check if near a wall
near_wall?(buffer: 50)  # true if within 50 units of any wall
near_wall?              # Uses default 50 unit buffer
```

### Thrust Cost Estimation

```ruby
# Calculate what a thrust will cost
thrust_cost(thrust_speed:, angle:)

# Example: check if you can afford a maneuver
cost = thrust_cost(thrust_speed: 5, angle: 90)
if cost <= energy
  thrust(speed: 5, angle: 90)
end
```

---

## Arena

- **Dimensions**: Variable (default 400x400)
- **Origin**: Bottom-left (0,0)
- **Angles**: 0 = East, 90 = North, 180 = West, 270 = South
- **Friction**: 0.92 default (velocity *= friction each chronon)
- **Max speed**: No hard cap (friction naturally limits sustained speed)

---

## Complete Example

```ruby
class Hunter
  include Rubowar::Rubot
  size :small  # Fast and agile

  def on_spawn
    @search_direction = 1
  end

  def act
    # Read sensing from previous chronon
    if probe_echo.found?
      engage_target
    elsif scan_echo.any_rubots?
      target = scan_echo.closest_rubot(to_x: x, to_y: y)
      aim_at(target.x, target.y)
    else
      search_for_targets
    end

    # Queue sensing for next chronon
    probe(:position, :velocity) if energy > 20
    scan(angle: 60, distance: 200) if energy > 15
  end

  private

  def engage_target
    # Aim at predicted position
    lead = calculate_lead(probe_echo)
    aim_at(probe_echo.x + lead[:x], probe_echo.y + lead[:y])

    # Fire if on target
    fire(15) if turret_diff.abs < 10 && energy > 30
  end

  def aim_at(tx, ty)
    target_angle = angle_to(target_x: tx, target_y: ty)
    @turret_diff = normalize_angle(target_angle - turret_angle)
    rotate_turret(@turret_diff.clamp(-25, 25))
  end

  def turret_diff
    @turret_diff || 0
  end

  def search_for_targets
    # Sweep turret back and forth
    rotate_turret(10 * @search_direction)
    @search_direction *= -1 if turret_angle.abs > 170
  end

  def calculate_lead(echo)
    return { x: 0, y: 0 } unless echo.velocity_x

    # Simple lead calculation
    dist = distance_to(target_x: echo.x, target_y: echo.y)
    time_to_target = dist / 18.0  # Bullet speed
    {
      x: echo.velocity_x * time_to_target,
      y: echo.velocity_y * time_to_target
    }
  end
end
```

---

## See Also

- [Tutorial](TUTORIAL.md) - Hands-on introduction
- [Sample Bots](SAMPLE_BOTS.md) - Study working examples
- [Physics](PHYSICS.md) - Detailed physics documentation
- [Debugging](DEBUGGING.md) - Debug tools and testing
