# Debugging

Rubowar includes several tools for developing and debugging your rubots.

## Test Harness

Quickly test your rubot against dummy opponents without setting up a full battle:

```ruby
# Basic test against a stationary target
result = Rubowar.test_battle(MyBot)
puts "Won: #{result[:won]}, Health: #{result[:test_rubot][:health]}"

# Test against multiple opponent types
result = Rubowar.test_battle(MyBot, opponents: [:spinner, :chaser])

# Watch the battle live in terminal
Rubowar.test_battle(MyBot, opponents: [:chaser], watch: true)

# Reproducible test with seed
result = Rubowar.test_battle(MyBot, seed: 12345)
puts "Seed: #{result[:seed]}"  # Save to replay exact battle

# Controlled starting position
Rubowar.test_battle(MyBot, position: {x: 100, y: 100})

# Run with debug output
result = Rubowar.test_battle(MyBot, debug: true)
```

### Test Harness Options

| Option | Default | Description |
|--------|---------|-------------|
| `opponents:` | `[:stationary]` | Array of dummy opponent types |
| `count:` | `1` | Number of each opponent type |
| `chronon_limit:` | `500` | Maximum chronons |
| `debug:` | `false` | Enable debug output |
| `watch:` | `false` | Show terminal visualization |
| `seed:` | `nil` | Random seed for reproducibility |
| `position:` | `nil` | Starting position `{x:, y:}` for test rubot |

### Dummy Opponents

| Type | Behavior |
|------|----------|
| `:stationary` | Does nothing - good for testing basic mechanics |
| `:spinner` | Spins turret and fires - tests dodging and return fire |
| `:chaser` | Moves toward nearest enemy - tests evasion |
| `:random` | Random movement and firing - unpredictable opponent |
| `:shielder` | Raises shields constantly - tests sustained damage |

### Test Results

```ruby
result = Rubowar.test_battle(MyBot)

result[:won]              # => true/false
result[:winner]           # => "MyBot" or opponent name
result[:chronons]         # => number of ticks
result[:seed]             # => seed for replay

result[:test_rubot][:health]        # => remaining HP
result[:test_rubot][:damage_dealt]  # => damage dealt
result[:test_rubot][:damage_taken]  # => damage taken
result[:test_rubot][:alive]         # => true/false

result[:opponents]        # => array of opponent stats
```

---

## Debug Helpers

Enable debug mode in your rubot to access debugging tools:

```ruby
class DebugBot
  include Rubowar::Rubot

  def on_spawn
    @debug = true
  end

  def act
    # Print current status
    warn status_summary if @debug
    # => [STATUS] pos=(100, 200) vel=(1.5, 2.0) speed=2.5 turret=45° HP=90/100 E=50 shield=0

    # Check if you can afford an action before trying
    if can_do?(:fire, energy_amount: 20)
      fire(20)
    else
      warn "Can't afford fire(20), need 20, have #{energy}" if @debug
    end

    # Get action costs to plan your energy budget
    thrust_cost = action_cost(:thrust, speed: 5, angle: 90)
    scan_cost = action_cost(:scan, angle: 60, distance: 200)
    warn "Thrust: #{thrust_cost}E, Scan: #{scan_cost}E" if @debug

    # Try action with automatic failure logging
    debug_action(:fire, 200)
    # => [DEBUG] fire failed: need 200 energy, have 50

    debug_action(:thrust, speed: 5, angle: 90)
    # => (succeeds silently, or logs failure reason)
  end
end
```

### Helper Methods

| Method | Description |
|--------|-------------|
| `status_summary` | One-line status string with position, velocity, HP, energy |
| `can_do?(action, **params)` | Check if you can afford an action |
| `action_cost(action, **params)` | Calculate energy cost of an action |
| `debug_action(action, *args, **kwargs)` | Execute action with automatic failure logging |
| `dump_sensing` | Print all sensing results from previous chronon |

---

## Sensing Visualization

See what your sensors detected:

```ruby
class SensorDebugBot
  include Rubowar::Rubot

  def on_spawn
    @debug = true
  end

  def act
    # Queue sensing actions
    probe(:position, :velocity)
    scan(angle: 90, distance: 300, velocity: true)
    pulse(distance: 200)

    # Dump results from previous chronon
    dump_sensing if @debug && chronon > 1
    # Output:
    # [SENSING] Chronon 5
    #   Probe: HIT - {size: :medium, x: 150.0, y: 200.0, velocity_x: 1.5, velocity_y: 0.0}
    #   Scan: 2 target(s)
    #     [0] rubot at (150.0, 200.0) vel=(1.5, 0.0)
    #     [1] bullet at (180.0, 210.0)
    #   Pulse: 1 target(s)
    #     [0] rubot at (150.0, 200.0)
    #   Detect: probed=1 scanned=0 pulsed=2
  end
end
```

---

## Deterministic Battles

Use seeds for reproducible battles - essential for debugging intermittent issues:

```ruby
# Seeded battle - same seed = same outcome
battle = Rubowar::Battle.local([Bot1, Bot2], seed: 12345)
battle.run
puts battle.seed  # => 12345

# Auto-generated seed (save for replay)
battle = Rubowar::Battle.local([Bot1, Bot2])
battle.run
puts battle.seed  # => 137238091658095901... (save this)

# Later, replay with same seed
replay = Rubowar::Battle.local([Bot1, Bot2], seed: battle.seed)
```

**What seeds control:**
- Spawn positions (when not explicitly set)
- Turret angles (when not explicitly set)
- Energon spawn locations
- Any `rand()` calls in the engine

**What seeds don't control:**
- `rand()` calls in your rubot code
- External factors (timing, network, etc.)

---

## Controlled Spawning

Test specific scenarios with controlled positions:

```ruby
event_bus = Rubowar::EventBus.new(chronon_limit: 100)
arena = Rubowar::Arena.new(width: 400, height: 400, event_bus:)
battle = Rubowar::Battle.new(arena:, event_bus:, seed: 12345)

# Spawn at exact positions with specific turret angles
battle.register(
  Rubowar::LocalActor.new(MyBot),
  position: {x: 100, y: 100},
  turret_angle: 0  # Facing right
)

battle.register(
  Rubowar::LocalActor.new(Enemy),
  position: {x: 300, y: 100},
  turret_angle: 180  # Facing left
)

battle.run
```

**Use cases:**
- Test head-to-head confrontations
- Debug corner cases
- Verify specific maneuvers
- Reproduce bug conditions

---

## Battle Statistics

Access detailed statistics after a battle:

```ruby
battle = Rubowar::Battle.local([Bot1, Bot2])
battle.run

stats = battle.stats

# Overall stats
puts stats.chronons       # => 342
puts stats.winner         # => "Bot1"
puts stats.outcome        # => :victory or :draw
puts stats.total_damage   # => 245.5
puts stats.seed           # => for replay

# Per-bot stats
stats.each do |id, bot|
  puts "#{bot[:name]}: #{bot[:damage_dealt]} dealt, #{bot[:damage_taken]} taken"
end

# Access specific bot
bot = stats[battle.winner.id]
puts "Winner HP: #{bot[:health]}/#{bot[:max_health]}"

# Human-readable summary
puts stats.to_s

# Export for analysis
File.write("stats.json", JSON.pretty_generate(stats.to_h))
```

See [BATTLES.md](BATTLES.md) for complete statistics documentation.

---

## Event Logging

Subscribe to events to see what's happening:

```ruby
battle = Rubowar::Battle.local([Bot1, Bot2])

battle.on(:action_failed) do |event|
  puts "[FAIL] #{event[:actor_id]}: #{event[:action]} - #{event[:reason]}"
end

battle.on(:error) do |event|
  puts "[ERROR] #{event[:actor_id]}: #{event[:error].message}"
end

battle.on(:death) do |event|
  puts "[DEATH] #{event[:actor_id]}"
end

battle.on(:hit) do |event|
  puts "[HIT] #{event[:actor_id]} took #{event[:damage]} damage"
end

battle.run
```

### All Event Types

| Event | Description | Key Data |
|-------|-------------|----------|
| `:chronon` | Each tick | `actors`, `bullets`, `energons` |
| `:death` | Rubot destroyed | `actor_id` |
| `:hit` | Bullet hit | `actor_id`, `bullet_id`, `damage` |
| `:error` | Rubot crashed | `actor_id`, `error` |
| `:action_failed` | Action failed | `actor_id`, `action`, `reason` |
| `:energon_spawn` | Energon appeared | `energon_id`, `x`, `y` |
| `:energon_collect` | Energon collected | `actor_id`, `amount` |
| `:battle_end` | Battle finished | `winner_id`, `winner_name`, `outcome` |

---

## Terminal Visualization

Watch battles in real-time:

```ruby
# Using test harness
Rubowar.test_battle(MyBot, watch: true)

# Manual setup
battle = Rubowar::Battle.local([Bot1, Bot2])
terminal = Rubowar::Renderers::Terminal.new(battle)

battle.on(:chronon) do |state|
  terminal.render(state)
  sleep 0.05  # Slow down for visibility
end

battle.run
terminal.render_final(battle.winner)
```

**Terminal output:**
```
╔════════════════════════════════════════╗
║  ·                                     ║
║      [A]→                              ║
║                    ●                   ║
║               ←[B]                     ║
║                                        ║
╚════════════════════════════════════════╝
Chronon: 42 | A: 85HP 67E | B: 72HP 45E
```

---

## JSON Logging

Record battles for detailed analysis:

```ruby
battle = Rubowar::Battle.local([Bot1, Bot2])
logger = Rubowar::Renderers::JsonLogger.new(battle)

events = battle.run

# Events are already in battle.event_log
File.write("replay.json", JSON.pretty_generate(battle.event_log))
```

Or use the CLI:
```bash
bin/log -o replay.json rubots/spinner.rb rubots/hunter.rb
```

---

## Common Debugging Patterns

### Finding Why an Action Failed

```ruby
def act
  # Check affordability first
  if can_do?(:fire, energy_amount: 30)
    fire(30)
  else
    cost = action_cost(:fire, energy_amount: 30)
    warn "Can't fire(30): need #{cost}, have #{energy}"
  end
end
```

### Tracing Target Acquisition

```ruby
def act
  if probe_echo.found?
    warn "[#{chronon}] Target at (#{probe_echo.x}, #{probe_echo.y})"
    warn "  Distance: #{distance_to(target_x: probe_echo.x, target_y: probe_echo.y)}"
    warn "  Turret angle: #{turret_angle}, target angle: #{angle_to(target_x: probe_echo.x, target_y: probe_echo.y)}"
  else
    warn "[#{chronon}] No target"
  end

  probe(:position)
end
```

### Debugging Movement

```ruby
def act
  warn "[#{chronon}] pos=(#{x.round(1)}, #{y.round(1)}) vel=(#{velocity_x.round(2)}, #{velocity_y.round(2)}) speed=#{speed.round(2)}"

  cost = thrust_cost(thrust_speed: 5, angle: 90)
  warn "  Thrust(5, 90°) would cost #{cost}E (have #{energy}E)"

  if energy >= cost
    thrust(speed: 5, angle: 90)
    warn "  -> Thrusting"
  end
end
```

### Debugging Collisions

```ruby
def on_collision(other:)
  warn "[COLLISION] Hit #{other.name} at (#{other.x.round}, #{other.y.round})"
  warn "  Other velocity: (#{other.velocity_x.round(2)}, #{other.velocity_y.round(2)})"
  warn "  My velocity: (#{velocity_x.round(2)}, #{velocity_y.round(2)})"
end

def on_wall
  warn "[WALL] Hit wall at (#{x.round}, #{y.round})"
end
```
