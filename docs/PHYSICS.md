# Physics System

Rubowar uses a momentum-based physics system with realistic collision responses. This document covers the physics engine internals and how they affect gameplay.

## Overview

The physics system consists of two main components:

- **Physics module** (`lib/rubowar/physics.rb`) - Pure stateless calculations
- **RubotPhysics module** (`lib/rubowar/rubot_physics.rb`) - Actor state mutations

All physics calculations use consistent units:
- **Distance**: units (arena is 400x400 by default)
- **Time**: chronons (game ticks)
- **Speed**: units/chronon
- **Mass**: relative to medium bot (1.0)

---

## Movement

### Thrust

Rubots move by thrusting in a world direction. There's no body angle - you can thrust in any direction regardless of orientation.

```ruby
thrust(speed: 5, angle: 90)  # Thrust upward (90°)
```

**Cost formula**: `(speed / 1.5)² × mass × direction_multiplier`

| Factor | Description |
|--------|-------------|
| `speed` | Requested thrust speed (0-∞) |
| `mass` | Bot mass (0.36 small, 1.0 medium, 1.96 large) |
| `direction_multiplier` | 1.0 (same direction) to 2.0 (opposite) |

**Direction multiplier**: Thrusting against your current momentum costs more:
- 0° from current heading: 1.0x cost
- 90° from current heading: 1.5x cost
- 180° from current heading: 2.0x cost (full reversal)

**Partial thrust**: If you lack energy for the full thrust, you get proportionally reduced speed rather than failure.

### Friction

Every chronon, velocity is multiplied by the friction coefficient (default 0.92):

```ruby
velocity_x *= 0.92
velocity_y *= 0.92
```

This means:
- After 10 chronons: ~43% of original velocity
- After 20 chronons: ~19% of original velocity
- Terminal velocity depends on thrust rate vs friction decay

### Speed

Speed is the magnitude of velocity:

```ruby
speed = Math.sqrt(velocity_x² + velocity_y²)
```

There's no hard speed cap. Friction naturally limits sustained speed, and high-speed collisions deal significant damage.

---

## Mass

Mass is derived from radius, relative to the medium bot:

```ruby
mass = (radius / 10.0)²  # 10 is medium radius
```

| Size | Radius | Mass | Effect |
|------|--------|------|--------|
| Small | 6 | 0.36 | Cheap thrust, weak collisions |
| Medium | 10 | 1.0 | Baseline |
| Large | 14 | 1.96 | Expensive thrust, powerful collisions |

Mass affects:
- **Thrust cost**: Higher mass = more energy to accelerate
- **Collision damage dealt**: Higher mass = more damage to others
- **Collision knockback**: Higher mass = less knockback received
- **Wall bounce**: Higher mass = more velocity retained

---

## Collisions

### Bot-Bot Collisions

When two bots overlap, the collision system:

1. **Separates** them (push apart equally)
2. **Bounces** velocities using impulse physics
3. **Applies damage** based on momentum
4. **Triggers callbacks** (`on_collision`)

**Damage formula**: `2 + other_mass × closing_speed × 0.5`

The damage you take depends on the *other* bot's mass and the closing speed between you.

**Bounce physics**: Uses conservation of momentum with elasticity 0.5:
- Both bots bounce off each other
- Heavier bots receive less velocity change
- Already-separating bots don't double-bounce

**Separation**: Overlapping bots are pushed apart equally. If positions are identical (extremely rare), they separate along the X-axis.

### Wall Collisions

When a bot hits a wall:

1. **Bounces** using impulse physics against the wall's effective mass
2. **Applies damage** based on impact momentum
3. **Triggers callback** (`on_wall`)
4. **Clamps position** inside arena bounds

**Damage formula**: `2 + mass × impact_speed × 0.5`

Note: Wall damage uses *your* mass (you're hitting a stationary wall), while bot collision damage uses the *other* bot's mass.

**Wall bounce elasticity**: 0.2 (walls are "sticky" - absorb most momentum)

The wall has an effective mass of 24.0, making it immovable but allowing heavier bots to retain more velocity:

| Size | Mass | Velocity Retained |
|------|------|------------------|
| Small | 0.36 | ~15% |
| Medium | 1.0 | ~21% |
| Large | 1.96 | ~27% |

Walls can't be used for free direction changes - they absorb most of your momentum.

---

## Bullets

### Movement

Bullets travel at constant 18 units/chronon (no friction, no acceleration).

```ruby
bullet.x += bullet.velocity_x  # Each chronon
bullet.y += bullet.velocity_y
```

**Speed comparison**:
- Bullet: 18 u/chronon (constant)
- Bot at max sustainable thrust: ~8-12 u/chronon (varies by size/energy)

Rubots can theoretically outrun bullets with sustained thrust, but it's extremely energy-expensive.

### Spawn Position

Bullets spawn at the edge of the firing rubot:

```ruby
spawn_distance = rubot_radius + bullet_radius  # bullet_radius = 3
spawn_x = rubot_x + cos(turret_angle) × spawn_distance
spawn_y = rubot_y + sin(turret_angle) × spawn_distance
```

**Self-damage**: If you're moving backward fast enough while firing forward, your bullet can hit you. This is rare but possible.

### Hit Detection

Bullets hit a rubot when:
```ruby
distance(bullet, rubot) < bullet_radius + rubot_radius
```

Bullets are removed when:
- They hit a rubot
- They leave the arena bounds

Bullets do NOT collide with each other.

---

## Turret Rotation

The turret has an angle independent of movement. Rotation costs energy:

```ruby
rotate_turret(degrees)  # Positive = clockwise, negative = counter-clockwise
```

**Cost formula**: `ceil(|degrees| / 24)`

| Rotation | Cost |
|----------|------|
| 1-24° | 1 energy |
| 25-48° | 2 energy |
| 49-72° | 3 energy |
| ... | ... |
| 180° | 8 energy |

---

## Configuration Constants

All physics constants are in `lib/rubowar/config.rb`:

### Arena
```ruby
DEFAULT_FRICTION = 0.92           # Velocity multiplier per chronon
DEFAULT_WIDTH = 400               # Arena width
DEFAULT_HEIGHT = 400              # Arena height
```

### Collisions
```ruby
COLLISION_BASE_DAMAGE = 2         # Minimum damage from any collision
COLLISION_VELOCITY_MULTIPLIER = 0.5  # Damage scaling with speed
COLLISION_ELASTICITY = 0.5        # Bot-bot bounce (moderate)
WALL_ELASTICITY = 0.2             # Wall bounce (sticky)
WALL_MASS = 24.0                  # Effective wall mass
```

### Thrust
```ruby
THRUST_MULTIPLIER = 1.5           # Divisor in cost formula
STATIONARY_SPEED_THRESHOLD = 0.1  # Below this, direction_multiplier = 1.0
```

### Bullets
```ruby
BULLET_SPEED = 18                 # Units per chronon
BULLET_RADIUS = 3                 # Collision radius
```

### Turret
```ruby
TURRET_TURN_DIVISOR = 24.0        # Degrees per energy
```

---

## Physics Module API

The `Physics` module provides pure calculation functions:

### Distance & Angles
```ruby
Physics.distance(x1:, y1:, x2:, y2:)  # Euclidean distance
Physics.normalize_angle(angle)         # Normalize to -180..180
```

### Collision Calculations
```ruby
Physics.collision_damage(rel_vx:, rel_vy:, mass:)
Physics.collision_bounce(a_vx:, a_vy:, b_vx:, b_vy:, nx:, ny:, mass_a:, mass_b:)
Physics.collision_separation(a_x:, a_y:, b_x:, b_y:, distance:, overlap:, ...)
```

### Wall Calculations
```ruby
Physics.wall_damage(vx:, vy:, normal_x:, normal_y:, mass:)
Physics.wall_bounce(vx:, vy:, normal_x:, normal_y:, bot_mass:)
```

### Thrust Calculations
```ruby
Physics.thrust_direction_multiplier(vx:, vy:, thrust_angle:, speed:)
Physics.thrust_cost(speed:, mass:, direction_multiplier:)
Physics.thrust_speed_from_energy(energy:, mass:, direction_multiplier:)
Physics.thrust_velocity(speed:, angle:, mass:)
```

### Mass
```ruby
Physics.mass_factor(radius)  # Memoized mass calculation
```

---

## RubotPhysics Module

The `RubotPhysics` module provides state-mutating methods for actors:

### Movement
```ruby
actor.thrust(speed:, angle:)   # Apply thrust (handles energy, partial thrust)
actor.move                     # Apply velocity to position
actor.apply_friction(friction) # Apply friction coefficient
```

### Position
```ruby
actor.set_position(x:, y:)
actor.adjust_position(dx:, dy:)
actor.clamp_x(min:, max:)
actor.clamp_y(min:, max:)
```

### Velocity
```ruby
actor.set_velocity(vx:, vy:)
actor.adjust_velocity(dvx:, dvy:)
```

### Turret
```ruby
actor.turret_angle = angle     # Set absolute angle
actor.turn_turret(degrees)     # Rotate by degrees (costs energy)
```

---

## Collision Response

Collisions are processed in two phases to prevent race conditions:

1. **Detection phase**: Calculate all collision responses as immutable `CollisionResponse` objects
2. **Application phase**: Apply all responses atomically

```ruby
CollisionResponse = Data.define(
  :actor_a, :actor_b,
  :pos_adjust_a_x, :pos_adjust_a_y,
  :pos_adjust_b_x, :pos_adjust_b_y,
  :vel_adjust_a_x, :vel_adjust_a_y,
  :vel_adjust_b_x, :vel_adjust_b_y,
  :damage_to_a, :damage_to_b
)
```

This ensures consistent behavior regardless of collision processing order.
