# Rubowar Tutorial

Welcome to Rubowar! This tutorial will walk you through building your first combat robot from scratch.

## What is Rubowar?

Rubowar is a programming game where you write Ruby code to control robots ("rubots") that fight in an arena. Your rubot's `act` method is called every "chronon" (game tick), and you decide what actions to take: move, sense enemies, fire weapons, raise shields.

Victory goes to the programmer who best anticipates and adapts.

## Part 1: Your First Rubot

Let's build a rubot step by step.

### The Bare Minimum

Every rubot needs three things:

```ruby
class MyFirstBot
  include Rubowar::Rubot  # 1. Include the Rubot module
  size :medium            # 2. Declare a size

  def act                 # 3. Implement the act method
    # Your code here
  end
end
```

This rubot does nothing - it just sits there. Let's make it dangerous.

### Adding Weapons

```ruby
class MyFirstBot
  include Rubowar::Rubot
  size :medium

  def act
    rotate_turret(10)  # Spin the turret
    fire(10)           # Shoot!
  end
end
```

Now it spins and shoots energy bullets blindly. But it wastes energy firing at nothing. Let's add sensing.

### Adding Sensing

```ruby
class MyFirstBot
  include Rubowar::Rubot
  size :medium

  def act
    # Sense: send out a probe along turret direction
    probe

    # Move: spin the turret
    rotate_turret(10)

    # Combat: only fire if we detected something LAST chronon
    fire(10) if probe_echo.found?
  end
end
```

**Important:** `probe` queues a sensing action, but results aren't available until the NEXT chronon in `probe_echo`. This 1-chronon delay is fundamental to Rubowar strategy.

**Note:** `probe_echo` is never nil - it returns an empty object if no target was found. Use `probe_echo.found?` to check if a target was detected.

### Adding Energy Management

```ruby
class MyFirstBot
  include Rubowar::Rubot
  size :medium

  def act
    probe

    rotate_turret(10)

    # Only fire if we have enough energy reserves
    fire(10) if probe_echo.found? && energy > 20
  end
end
```

Medium rubots regenerate 10 energy per chronon. By keeping a reserve of 20, we ensure we can always sense and move.

**Congratulations!** You've just built the Spinner bot - a simple but functional rubot.

## Part 2: Understanding the Game Loop

### Chronons and Phases

Each chronon (game tick) processes actions in phases:

```
1. SENSE   → All probe(), scan(), pulse(), detect() for ALL rubots
2. MOVE    → All thrust(), rotate_turret() for ALL rubots, then physics
3. COMBAT  → All fire(), raise_shields() for ALL rubots, then bullet physics
```

**Key insight:** All rubots act simultaneously within each phase to reduce "first mover" advantage.

### The Sensing Delay

This is the most important concept in Rubowar:

```
Chronon 1: You call probe()        → Probe executes, finds enemy at (100, 200)
Chronon 2: probe_echo = {x: 100, y: 200}  → NOW you can see the result
           Enemy has moved to (110, 205)   → Data is already stale!
```

Your sensing data is always 1 chronon old. Good rubots predict where enemies WILL be, not where they WERE.

### Energy Flow

```
Start of chronon:  energy = 45
  → probe()           costs 1  → energy = 44
  → rotate_turret(10) costs 1  → energy = 43
  → fire(10)          costs 10 → energy = 33
End of chronon:    +10 regen  → energy = 43
```

Energy regenerates at the end of each chronon. Budget carefully!

## Part 3: Movement

### Basic Thrust

```ruby
def act
  thrust(speed: 5, angle: 90)  # Move north (90° = up)
end
```

Angles are in world coordinates:
- 0° = East (right)
- 90° = North (up)
- 180° = West (left)
- 270° = South (down)

### Momentum Matters

Rubowar has realistic physics. Your rubot has momentum:

```ruby
def act
  # If moving east and you thrust west, it costs 2x energy!
  # Thrust WITH your momentum for efficiency

  cost = thrust_cost(thrust_speed: 5, angle: 90)
  puts "This thrust will cost #{cost} energy"

  thrust(speed: 5, angle: 90) if cost <= energy - 20
end
```

Use `thrust_cost` to calculate the actual cost before committing.

### Friction

Arena friction is 0.92 - you lose 8% speed each chronon. Without thrust, you'll coast to a stop.

## Part 4: Sensing in Depth

### Three Sensing Modes

| Method  | Coverage                | Returns                      | Best For              |
|---------|-------------------------|------------------------------|-----------------------|
| `probe` | Line (turret direction) | Single target, detailed info | Precise targeting     |
| `scan`  | Arc (cone)              | Multiple targets, positions  | Searching an area     |
| `pulse` | Circle (360°)           | Multiple targets, positions  | Situational awareness |

### Probe - Precision Targeting

```ruby
probe                         # 1 energy - just detection
probe(:position)              # 5 energy - get x, y
probe(:position, :velocity)   # 8 energy - get x, y, velocity_x, velocity_y

# Results in probe_echo NEXT chronon (ProbeEcho object):
probe_echo.found?             # true if target detected
probe_echo.size               # :medium
probe_echo.x                  # 150.0
probe_echo.y                  # 200.0
probe_echo.velocity_x         # 2.0 (if requested)
probe_echo.velocity_y         # -1.0 (if requested)
```

### Scan - Area Search

```ruby
scan(angle: 60, distance: 200)                  # 7 energy - 60° arc, 200 units
scan(angle: 60, distance: 200, velocity: true)  # 9 energy - includes velocity

# Results in scan_echo NEXT chronon (ScanEcho object):
scan_echo.empty?              # true if no targets found
scan_echo.any_rubots?         # are there any rubots?
scan_echo.any_bullets?        # are there any bullets?
scan_echo.rubots              # filter to only rubots
scan_echo.bullets             # filter to only bullets
scan_echo.closest_rubot(to_x: x, to_y: y)  # find nearest rubot

# Each target is a SenseTarget with attributes:
target.x                      # 150.0
target.y                      # 200.0
target.type                   # :rubot or :bullet
target.velocity_x             # 2.0 (if velocity: true)
```

### Pulse - 360° Radar

```ruby
pulse(distance: 150)  # 4 energy - everything within 150 units

# Results in pulse_echo NEXT chronon (PulseEcho object):
# Same API as ScanEcho - use any_rubots?, closest_rubot(), etc.
pulse_echo.any_rubots?
closest = pulse_echo.closest_rubot(to_x: x, to_y: y)
```

### Counter-Intelligence with Detect

```ruby
detect  # 2 energy - who's watching me?

# Results in detect_intel NEXT chronon (DetectIntel object):
detect_intel.targeted?        # true if sensed by anyone
detect_intel.probed           # 1 (times probed this chronon)
detect_intel.scanned          # 2 (times scanned)
detect_intel.pulsed           # 0 (times pulsed)
```

If `detect_intel.probed > 0`, someone has their turret pointed at you!

## Part 5: Combat

### Firing

```ruby
fire(energy_amount)  # Damage = energy × 1.5
```

- `fire(10)` costs 10 energy, deals 15 damage
- `fire(20)` costs 20 energy, deals 30 damage
- Energy bullets travel at 18 units/chronon

### Shields

```ruby
raise_shields(10)  # Convert 10 energy to 10 shield points
```

- Shields absorb damage before health
- Shields decay 12% per chronon
- Max shield = max health

### Leading Your Target

Enemies move. Bullets take time to travel. You need to aim where they WILL be. The `lead_position` helper calculates this:

```ruby
lead_x, lead_y = lead_position(
  target_x: target[:x],
  target_y: target[:y],
  velocity_x: target[:velocity_x],
  velocity_y: target[:velocity_y]
)
target_angle = angle_to(target_x: lead_x, target_y: lead_y)
```

See the Tracker bot (`robots/tracker.rb`) for a complete example using the `SimpleTargeting` mixin, which handles lead calculation for you.

## Part 6: Putting It Together

Here's a complete intermediate bot:

```ruby
class MyHunter
  include Rubowar::Rubot
  size :medium

  def on_spawn
    @search_direction = 1
  end

  def act
    if probe_echo.found? && probe_echo.x
      # We have a target - attack!
      attack_target
    elsif scan_echo.any_rubots?
      # Found something in scan - probe it
      target = scan_echo.closest_rubot(to_x: x, to_y: y)
      aim_at(target.x, target.y)
      probe(:position, :velocity)
    else
      # No target - search
      search_for_targets
    end
  end

  private

  def attack_target
    target_x = probe_echo.x
    target_y = probe_echo.y

    # Lead the target if we have velocity data
    if probe_echo.velocity_x
      target_x, target_y = lead_position(
        target_x: target_x, target_y: target_y,
        velocity_x: probe_echo.velocity_x,
        velocity_y: probe_echo.velocity_y
      )
    end

    aim_at(target_x, target_y)

    # Fire when aligned and we have energy
    diff = normalize_angle(angle_to(target_x: target_x, target_y: target_y) - turret_angle)
    fire(12) if diff.abs < 15 && energy > 30

    # Keep probing to maintain lock
    probe(:position, :velocity)
  end

  def aim_at(target_x, target_y)
    target_angle = angle_to(target_x: target_x, target_y: target_y)
    diff = normalize_angle(target_angle - turret_angle)
    rotate_turret(diff.clamp(-20, 20))
  end

  def search_for_targets
    # Alternate between scanning and pulsing
    if chronons % 3 == 0
      pulse(distance: 300)
    else
      rotate_turret(15 * @search_direction)
      scan(angle: 90, distance: 400)
    end

    # Change search direction occasionally
    @search_direction *= -1 if chronons % 50 == 0
  end
end
```

## Part 7: Debugging Tips

### Print Statements

```ruby
def act
  puts "Chronon #{chronons}: energy=#{energy}, health=#{health}"
  puts "  probe_echo: #{probe_echo.inspect}"
  # ... rest of act
end
```

### Common Mistakes

1. **Checking probe_echo immediately after probe()**
   ```ruby
   # WRONG - probe_echo is from LAST chronon
   probe(:position)
   fire(10) if probe_echo.x  # This is old data!
   ```

2. **Forgetting energy costs**
   ```ruby
   # WRONG - might not have enough energy
   scan(angle: 360, distance: 500)  # 14 energy!
   fire(20)                          # 20 energy!
   thrust(speed: 6, angle: 90)       # 16+ energy!
   # Total: 50+ energy in one chronon
   ```

3. **Not normalizing angles**
   ```ruby
   # WRONG - angle might be outside -180..180
   diff = target_angle - turret_angle

   # RIGHT
   diff = normalize_angle(target_angle - turret_angle)
   ```

4. **Ignoring momentum costs**
   ```ruby
   # Could cost 16 energy OR 32 energy depending on current velocity!
   thrust(speed: 6, angle: 90)

   # Better: check first
   cost = thrust_cost(thrust_speed: 6, angle: 90)
   thrust(speed: 6, angle: 90) if cost <= energy - 20
   ```

## Part 8: Size Strategy

| Size      | HP  | Regen       | Movement Cost | Playstyle                 |
|-----------|-----|-------------|---------------|---------------------------|
| `:small`  | 80  | 8/chronon   | Cheapest      | Agile dodger, hard to hit |
| `:medium` | 100 | 10/chronon  | Medium        | Balanced                  |
| `:large`  | 120 | 12/chronon  | Expensive     | Tanky, high firepower     |

Choose based on your strategy:
- **Small**: Evasion-focused, hit-and-run
- **Medium**: Flexible, good for learning
- **Large**: Turret/tank style, high damage output

## Next Steps

1. **Run battles**: Test your bot against the sample bots
2. **Study the samples**: Read `SAMPLE_BOTS.md` and the code in `robots/`
3. **Iterate**: Watch battles, identify weaknesses, improve
4. **Experiment**: Try different sizes, strategies, and tactics

Remember: The best bot depends on what you're fighting against. Adapt!

## Quick Reference

### Actions
| Action                    | Cost                        | Effect       |
|---------------------------|-----------------------------|--------------|
| `thrust(speed:, angle:)`  | `(speed/1.5)² × mass × dir` | Add velocity |
| `rotate_turret(degrees)`  | `ceil(\|degrees\|/24)`      | Turn turret  |
| `fire(energy)`            | `energy`                    | Shoot (damage = 1.5×) |
| `raise_shields(energy)`   | `energy`                    | Add shield   |

### Sensing
| Sensor                    | Cost | Delay     | Returns                 |
|---------------------------|------|-----------|-------------------------|
| `probe(*attrs)`           | 1-18 | 1 chronon | Single target, detailed |
| `scan(angle:, distance:)` | 5-15 | 1 chronon | Multiple targets in arc |
| `pulse(distance:)`        | 3-6  | 1 chronon | All targets in radius   |
| `detect`                  | 2    | 1 chronon | Counter-intel counts    |

### Utility Methods
| Method                               | Purpose                      |
|--------------------------------------|------------------------------|
| `distance_to(target_x:, target_y:)`  | Distance to point            |
| `angle_to(target_x:, target_y:)`     | Angle to point               |
| `normalize_angle(angle)`             | Clamp to -180..180           |
| `lead_position(...)`                 | Predict target position      |
| `thrust_cost(thrust_speed:, angle:)` | Calculate thrust energy cost |
| `near_wall?(buffer)`                 | Check if near arena edge     |
| `velocity_angle`                     | Current movement direction   |

Good luck, and happy hunting!
