# Battles

This document covers battle mechanics, configuration, and APIs for running and analyzing Rubowar battles.

## Creating Battles

### Quick Start

```ruby
# Simple battle with two rubots
battle = Rubowar::Battle.local([Bot1, Bot2])
battle.run
puts "Winner: #{battle.winner&.name}"
```

### Battle.local Options

```ruby
Rubowar::Battle.local(
  [Bot1, Bot2],           # Array of rubot classes
  width: 400,             # Arena width (default: 400)
  height: 400,            # Arena height (default: 400)
  friction: 0.92,         # Friction coefficient (default: 0.92)
  chronon_limit: 9000,    # Max chronons before timeout (default: 9000)
  seed: 12345             # Random seed for reproducibility (default: auto-generated)
)
```

### Manual Battle Setup

For more control, create the battle components manually:

```ruby
event_bus = Rubowar::EventBus.new(chronon_limit: 1000)
arena = Rubowar::Arena.new(width: 400, height: 400, friction: 0.92, event_bus:)
battle = Rubowar::Battle.new(arena:, event_bus:, seed: 12345)

# Register actors with optional positioning
battle.register(Rubowar::LocalActor.new(Bot1), position: {x: 100, y: 100}, turret_angle: 0)
battle.register(Rubowar::LocalActor.new(Bot2), position: {x: 300, y: 300}, turret_angle: 180)

battle.run
```

---

## Chronon Phases

Each chronon (game tick) executes in this order:

1. **Collect Actions** - Call each rubot's `act` method, which queues actions by phase
2. **Sense Phase** - Process sensing actions (probe, scan, pulse, then detect)
3. **Move Phase** - Process movement actions (thrust, turret rotation), then update physics
4. **Combat Phase** - Process combat actions (fire, shield), then update bullet physics
5. **Energon Phase** - Check energon collection, spawn new energons
6. **Maintenance** - Regenerate energy, degrade shields, check for deaths

**Fairness**: All rubots queue their actions first, then each phase processes all rubots simultaneously. No rubot gets an advantage from execution order.

**Concurrency**: All `act()` calls run concurrently with a 0.5 second deadline. Rubots that exceed the deadline or crash have their actions cleared for that chronon.

---

## Victory Conditions

A battle ends when:
- **One rubot remains** - That rubot wins
- **All rubots dead** - Draw (mutual destruction)
- **Chronon limit reached** - Tiebreaker rules apply

### Tiebreaker (when chronon limit reached)

1. **Most damage dealt** wins
2. If tied, **highest HP percentage** wins

```ruby
# Default chronon limit is 9,000
battle = Rubowar::Battle.local([Bot1, Bot2], chronon_limit: 5000)
```

---

## Events

Battles emit events that renderers and analysis tools can consume.

### Subscribing to Events

```ruby
battle = Rubowar::Battle.local([Bot1, Bot2])

# Subscribe before running
battle.on(:chronon) { |state| render_frame(state) }
battle.on(:death) { |event| puts "#{event[:actor_id]} died!" }
battle.on(:battle_end) { |event| puts "Winner: #{event[:winner_name]}" }

battle.run
```

### Event Types

| Event | Description | Data |
|-------|-------------|------|
| `:chronon` | Full state each tick | `actors`, `bullets`, `energons`, `chronon` |
| `:death` | Rubot destroyed | `actor_id` |
| `:hit` | Bullet hit a rubot | `actor_id`, `bullet_id`, `damage` |
| `:error` | Rubot code crashed | `actor_id`, `error` |
| `:action_failed` | Action couldn't execute | `actor_id`, `action`, `reason` |
| `:energon_spawn` | Energon appeared | `energon_id`, `x`, `y` |
| `:energon_spawn_failed` | Spawn blocked (too crowded) | - |
| `:energon_collect` | Rubot collected energon | `actor_id`, `energon_id`, `amount` |
| `:battle_end` | Battle concluded | `winner_id`, `winner_name`, `outcome` |

### Event Log

All events are collected in `battle.event_log`:

```ruby
battle.run
events = battle.event_log

# Filter for specific events
deaths = events.select { |e| e[:type] == :death }
puts "#{deaths.size} rubots died"

# Save for replay
File.write("replay.json", JSON.pretty_generate(events))
```

---

## Deterministic Battles

Use seeds for reproducible battles - same seed with same rubots produces identical results.

### Seeded Battles

```ruby
# Explicit seed - reproducible
battle = Rubowar::Battle.local([Bot1, Bot2], seed: 12345)
battle.run
puts battle.seed  # => 12345

# Run again with same seed = same outcome
battle2 = Rubowar::Battle.local([Bot1, Bot2], seed: 12345)
battle2.run
# battle2.winner will be the same as battle.winner
```

### Auto-Generated Seeds

```ruby
# No seed provided - auto-generates one
battle = Rubowar::Battle.local([Bot1, Bot2])
battle.run

# Save the seed for replay
puts battle.seed  # => 137238091658095901...

# Later, replay exact battle
replay = Rubowar::Battle.local([Bot1, Bot2], seed: battle.seed)
```

### What Seeds Control

- Spawn positions (when not explicitly set)
- Turret angles (when not explicitly set)
- Energon spawn locations
- Any `rand()` calls in the engine

**Note**: Seeds do NOT affect randomness inside rubot code. If your rubot uses `rand()`, that's not controlled by the battle seed.

---

## Controlled Spawning

Override random spawning for testing specific scenarios:

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
  turret_angle: 180  # Facing left (toward MyBot)
)

battle.run
```

### Partial Control

You can control position but let turret angle be random, or vice versa:

```ruby
# Fixed position, random turret
battle.register(actor, position: {x: 200, y: 200})

# Random position, fixed turret
battle.register(actor, turret_angle: 90)
```

---

## Battle Statistics

Access detailed statistics after a battle completes.

### Basic Usage

```ruby
battle = Rubowar::Battle.local([Bot1, Bot2])
battle.run

stats = battle.stats
```

### Overall Statistics

```ruby
stats.chronons       # => 342 (number of ticks)
stats.seed           # => 12345 (for replay)
stats.winner         # => "Bot1" (name, or nil for draw)
stats.winner_id      # => "rbot-a1b2c3d4" (ID, or nil)
stats.outcome        # => :victory or :draw
stats.total_damage   # => 245.5 (all damage dealt)
stats.alive_count    # => 1 (survivors)
stats.death_count    # => 1 (casualties)
```

### Per-Bot Statistics

```ruby
# List all bot IDs
stats.bot_ids  # => ["rbot-a1b2c3d4", "rbot-e5f6g7h8"]

# Access specific bot by ID
bot = stats["rbot-a1b2c3d4"]
bot[:name]           # => "Bot1"
bot[:health]         # => 45.5
bot[:max_health]     # => 90
bot[:energy]         # => 67.0
bot[:damage_dealt]   # => 150.5
bot[:damage_taken]   # => 44.5
bot[:alive]          # => true
bot[:x]              # => 200.5
bot[:y]              # => 150.3
bot[:turret_angle]   # => 127.5

# Iterate over all bots
stats.each do |id, bot|
  puts "#{bot[:name]}: #{bot[:damage_dealt]} damage dealt"
end
```

### Human-Readable Summary

```ruby
puts stats.to_s

# Output:
# Battle Stats (342 chronons, seed: 12345)
#   Outcome: victory - Winner: Bot1
#   Total damage: 245.5
#
#   Bots:
#     Bot1 (rbot-a1b2...): alive
#       HP: 45.5/90 | Energy: 67.0
#       Damage dealt: 150.5 | Damage taken: 44.5
#     Bot2 (rbot-e5f6...): dead
#       HP: 0.0/90 | Energy: 0.0
#       Damage dealt: 95.0 | Damage taken: 150.5
```

### Serialization

```ruby
# Convert to hash for JSON export
hash = stats.to_h
# => {
#   chronons: 342,
#   seed: 12345,
#   winner: "Bot1",
#   winner_id: "rbot-a1b2c3d4",
#   outcome: :victory,
#   total_damage: 245.5,
#   alive_count: 1,
#   death_count: 1,
#   bots: { "rbot-a1b2c3d4" => {...}, "rbot-e5f6g7h8" => {...} }
# }

# Save to file
File.write("stats.json", JSON.pretty_generate(stats.to_h))
```

---

## Error Handling

### Rubot Errors

If a rubot's `act` method raises an exception or times out:
- **20 damage** applied to that rubot
- Actions for that chronon are cleared (rubot does nothing)
- Battle continues

```ruby
battle.on(:error) do |event|
  puts "Rubot #{event[:actor_id]} crashed: #{event[:error].message}"
end
```

### Action Failures

Actions can fail for various reasons (insufficient energy, invalid parameters, etc.):

```ruby
battle.on(:action_failed) do |event|
  puts "#{event[:actor_id]}: #{event[:action]} failed - #{event[:reason]}"
end
```

---

## Test Harness

For quick testing during development, use the test harness:

```ruby
# Test against dummy opponents
result = Rubowar.test_battle(MyBot, opponents: [:spinner, :chaser])

puts result[:won]                    # => true/false
puts result[:test_rubot][:health]    # => 45.5
puts result[:seed]                   # => save for replay

# Watch live
Rubowar.test_battle(MyBot, watch: true)

# Controlled starting position
Rubowar.test_battle(MyBot, position: {x: 100, y: 100})
```

**Dummy opponents**: `:stationary`, `:spinner`, `:chaser`, `:random`, `:shielder`

See the [Debugging section](../README.md#debugging) in the README for more testing tools.
