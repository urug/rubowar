# Custom Actors

For advanced use cases (web interfaces, AI training, network play), you can create custom actors that control rubots externally rather than through local Ruby code.

## Overview

The default way to run a battle uses `LocalActor`, which wraps a Ruby class that includes the `Rubot` module:

```ruby
battle = Rubowar::Battle.local([MyBot, OpponentBot])
battle.run
```

But Rubowar's actor system is designed to be extensible. You can create custom actors that receive state updates and provide actions through any mechanism - WebSockets, HTTP APIs, message queues, etc.

---

## Battle Registration Model

Battles use a registration model where actors are registered before the battle starts:

```ruby
# Convenience method for local rubot classes (most common)
battle = Rubowar::Battle.local([MyBot, OpponentBot])
battle.run

# Low-level API for custom actors
event_bus = Rubowar::EventBus.new(chronon_limit: 9000)
arena = Rubowar::Arena.new(width: 640, height: 640, event_bus: event_bus)
battle = Rubowar::Battle.new(arena: arena, event_bus: event_bus)
battle.register(Rubowar::LocalActor.new(MyBot))
battle.register(my_custom_actor)
battle.run
```

---

## Actor Interface

All actors must implement the duck type interface that `Battle` expects. The core interface includes:

### Required State
```ruby
actor.id                    # UUID for identification
actor.name                  # Display name
actor.x, actor.y            # Position
actor.health, actor.energy  # Resources
actor.actions               # => { sense: [], move: [], combat: [] }
actor._act_completed        # Flag for deadline tracking
```

### Required Methods
```ruby
actor.act                   # Called each chronon (can be no-op for external control)
actor.alive?, actor.dead?   # Lifecycle status
actor.to_state              # => RubotState snapshot
actor.reset_actions         # Clear queued actions
```

### Building Custom Actors

The easiest way is to include the `RubotActor` and `RubotPhysics` modules:

```ruby
class WebActor
  include Rubowar::RubotActor
  include Rubowar::RubotPhysics

  attr_reader :rubot_class

  def initialize(size: :medium, name: "WebPlayer")
    initialize_actor(size:)
    @rubot_class = Class.new { define_singleton_method(:name) { name } }
    @_actions = { sense: [], move: [], combat: [] }
  end

  def instance = self
  def rubot_actions = @_actions
  def reset_actions = @_actions = { sense: [], move: [], combat: [] }
  def rubot_state=(state) = @_rubot_state = state
  def arena_state=(state) = @_arena_state = state
  def _pending_energy_spend=(val) = @_pending_energy_spend = val

  # Called each chronon - for external actors, this is a no-op
  # Actions are set externally via set_actions before the deadline
  def act; end

  # External control: set actions before Battle's chronon deadline (0.5s)
  def set_actions(sense: [], move: [], combat: [])
    @_actions = { sense:, move:, combat: }
  end

  # Sensing results storage and accessors.
  # LocalActor delegates these to the Rubot instance, but custom actors
  # must implement their own storage since there's no rubot instance.
  def set_sensing_results(probe: nil, scan: nil, pulse: nil, detect: nil)
    @probe_echo = Rubowar::ProbeEcho.from_hash(probe) unless probe.nil?
    @scan_echo = Rubowar::ScanEcho.new(scan) unless scan.nil?
    @pulse_echo = Rubowar::PulseEcho.new(pulse) unless pulse.nil?
    @detect_intel = Rubowar::DetectIntel.from_hash(detect) unless detect.nil?
  end

  attr_reader :probe_echo, :scan_echo, :pulse_echo, :detect_intel

  # Callbacks (override as needed) - all use keyword arguments
  def call_safely = block_given? ? yield(self) : nil
  def call_on_death; end
  def on_spawn; end
  def on_hit(damage:, direction:); end
  def on_wall; end
  def on_collision(other:); end  # other is a RubotState
  def on_energon(amount:); end
  def on_death; end
end
```

---

## Using Custom Actors

```ruby
# Create battle with custom actor
event_bus = Rubowar::EventBus.new(chronon_limit: 1000)
arena = Rubowar::Arena.new(event_bus: event_bus)
battle = Rubowar::Battle.new(arena: arena, event_bus: event_bus)

web_player = WebActor.new(size: :medium, name: "Player1")
battle.register(web_player)
battle.register(Rubowar::LocalActor.new(Spinner))

# In a separate thread/process, set actions before each chronon deadline
web_player.set_actions(
  sense: [{ type: :probe, attributes: [:position] }],
  move: [{ type: :thrust, speed: 5, angle: 90 }],
  combat: [{ type: :fire, energy: 10 }]
)

battle.run
```

---

## Action Format

Actions are hashes organized by phase:

```ruby
{
  sense: [
    { type: :probe, attributes: [:position, :velocity] },
    { type: :scan, angle: 60, distance: 200, velocity: true },
    { type: :pulse, distance: 150 },
    { type: :detect }
  ],
  move: [
    { type: :thrust, speed: 5, angle: 90 },
    { type: :rotate_turret, degrees: 15 }
  ],
  combat: [
    { type: :fire, energy: 20 },
    { type: :shield, energy: 10 }
  ]
}
```

### Sense Actions
| Type | Parameters | Description |
|------|------------|-------------|
| `:probe` | `attributes:` | Line-of-sight detection in turret direction |
| `:scan` | `angle:`, `distance:`, `velocity:`, `owner:` | Arc scan for multiple targets |
| `:pulse` | `distance:`, `owner:` | Omnidirectional radar ping |
| `:detect` | - | Counter-intelligence (how many times you were sensed) |

### Move Actions
| Type | Parameters | Description |
|------|------------|-------------|
| `:thrust` | `speed:`, `angle:` | Add velocity in world direction |
| `:rotate_turret` | `degrees:` | Rotate turret (negative = left) |

### Combat Actions
| Type | Parameters | Description |
|------|------------|-------------|
| `:fire` | `energy:` | Fire projectile (damage = 1.5 x energy) |
| `:shield` | `energy:` | Pump energy into shields |

---

## Chronon Deadline

Custom actors must set their actions before the chronon deadline (default 0.5 seconds). The battle loop:

1. Calls `actor.act` for all actors concurrently
2. Waits up to 0.5 seconds for all to complete
3. Processes actions for actors that completed in time
4. Actors that missed the deadline have empty actions (no-op)

For external actors, `act` is typically a no-op. The external system should call `set_actions` before the deadline expires.

---

## BasicActor

Rubowar includes `BasicActor` as a minimal reference implementation for testing and external control:

```ruby
# BasicActor is useful for:
# - Unit testing battle mechanics
# - Simple external control scenarios
# - Reference implementation for custom actors

actor = Rubowar::BasicActor.new(size: :medium, name: "TestBot")
actor.set_actions(
  move: [{ type: :thrust, speed: 3, angle: 45 }],
  combat: [{ type: :fire, energy: 15 }]
)
```

See `lib/rubowar/basic_actor.rb` in the source for the full implementation.

---

## Web Interface Example

Here's a conceptual example of a web-based actor:

```ruby
class WebSocketActor < WebActor
  def initialize(socket:, **opts)
    super(**opts)
    @socket = socket
    @pending_actions = { sense: [], move: [], combat: [] }

    # Listen for actions from client
    @socket.on(:message) do |data|
      @pending_actions = JSON.parse(data, symbolize_names: true)
    end
  end

  def act
    # Copy pending actions (set by WebSocket messages)
    @_actions = @pending_actions.dup

    # Send current state to client
    @socket.send(JSON.generate({
      x: x, y: y,
      health: health, energy: energy,
      turret_angle: turret_angle,
      probe: probe_echo&.to_h,
      scan: scan_echo&.targets
    }))
  end
end
```

This allows a web client to receive state updates and send actions in real-time.
