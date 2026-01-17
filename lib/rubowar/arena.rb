# frozen_string_literal: true

# [file]
# purpose = "Physics engine for the Rubowar battle arena"
# responsibility = "Movement, collisions, bullets, sensing, energon spawning"
# pattern = "Game Engine / Simulation"
#
# [class.Arena]
# purpose = "Manages all physical interactions in the battle space"
# input = "Rubot actions (thrust, fire, scan, etc.)"
# output = "Updated positions, damage events, sensing results"
# collaborators = ["RubotActor", "Bullet", "Energon", "Battle"]
#
# [constants]
# physics = [
#   "COLLISION_BASE_DAMAGE - Base damage for any collision (2)",
#   "COLLISION_VELOCITY_MULTIPLIER - Damage scaling with speed (0.5)",
#   "COLLISION_ELASTICITY - Bounce elasticity (0.5)",
#   "DEFAULT_FRICTION - Velocity decay per chronon (0.92)"
# ]
#
# [collaborators]
# CollisionSystem = "Handles rubot-rubot and wall collision detection/resolution"
# sensing = [
#   "Probe - Check turret line for target, returns attributes",
#   "Scan - Arc scan from turret, returns positions in cone",
#   "Pulse - Omnidirectional radar ping, returns nearby objects",
#   "Detect - Counter-intelligence, reports who scanned you"
# ]

module Rubowar
  class Arena
    attr_reader :width, :height, :friction, :event_bus
    attr_accessor :bullets, :actors, :energons

    def initialize(event_bus:, width: Config::Arena::DEFAULT_WIDTH, height: Config::Arena::DEFAULT_HEIGHT,
                   friction: Config::Arena::DEFAULT_FRICTION)
      @width = width
      @height = height
      @friction = friction
      @event_bus = event_bus
      @bullets = []
      @actors = []
      @energons = []
    end

    # Spawn distance calculations based on arena size
    def arena_diagonal
      Math.sqrt((@width**2) + (@height**2))
    end

    def spawn_wall_buffer
      ([@width, @height].min * Config::Arena::SPAWN_WALL_BUFFER_RATIO).round
    end

    def spawn_min_distance
      (arena_diagonal * Config::Arena::SPAWN_MIN_DISTANCE_RATIO).round
    end

    def spawn_max_distance
      (arena_diagonal * Config::Arena::SPAWN_MAX_DISTANCE_RATIO).round
    end

    def spawn_rubots(actors)
      actors.each { |actor| place_actor(actor) }
    end

    def place_actor(actor)
      position = find_spawn_position(actor.radius)
      actor.set_position(x: position[:x], y: position[:y])
      actor.turret_angle = rand(360)
      @actors << actor
    end

    def to_state(chronon)
      ArenaState.new(
        arena_width: @width,
        arena_height: @height,
        friction: @friction,
        chronon:,
        energons: @energons.map { |e| { x: e.x, y: e.y }.freeze }.freeze,
        live_rubot_count: @actors.count(&:alive?),
        energon_spawn_interval: Config::Arena::ENERGON_SPAWN_INTERVAL,
        energon_growth_rate: Config::Energon::GROWTH_RATE
      )
    end

    # Phase 2 physics: Move rubots, apply friction, handle collisions
    def update_rubot_physics
      @actors.each do |actor|
        next if actor.dead?

        actor.apply_friction(@friction)
        actor.move

        wall_result = CollisionSystem.process_wall_collision(actor:, arena_width: @width, arena_height: @height)
        next unless wall_result

        @event_bus.emit(EventBus::WallHit.new(
                          actor_id: actor.id,
                          damage: wall_result[:damage],
                          walls: wall_result[:walls]
                        ))
      end

      collision_responses = CollisionSystem.process_rubot_collisions(@actors)
      collision_responses.each do |response|
        @event_bus.emit(EventBus::Collision.new(
                          actor_a_id: response.actor_a.id,
                          actor_b_id: response.actor_b.id,
                          damage_to_a: response.damage_to_a,
                          damage_to_b: response.damage_to_b
                        ))
      end
    end

    # Phase 3 physics: Move bullets, check hits
    def update_bullet_physics
      update_bullets
    end

    # Returns true if action succeeded, false if it failed (e.g., insufficient energy)
    def process_action(actor:, action:)
      case action[:type]
      when :thrust
        actor.thrust(speed: action[:speed], angle: action[:angle])
      when :rotate_turret
        actor.turn_turret(action[:degrees])
      when :fire
        process_fire(actor:, energy: action[:energy])
      when :shield
        process_shield(actor:, energy: action[:energy])
      when :probe
        process_probe(actor:, attributes: action[:attributes])
      when :scan
        process_scan(actor:, angle: action[:angle], distance: action[:distance], velocity: action[:velocity],
                     owner: action[:owner])
      when :pulse
        process_pulse(actor:, distance: action[:distance], owner: action[:owner])
      when :detect
        actor.process_detect
      else
        false
      end
    end

    def regenerate_and_degrade
      @actors.each do |actor|
        next if actor.dead?

        actor.regenerate_energy
        actor.degrade_shield
      end
    end

    def find_spawn_position(radius)
      # Find already-placed actors
      placed_positions = @actors
                         .select(&:position_set)
                         .map { |r| { x: r.x, y: r.y } }

      SpawnPositionCalculator.find_rubot_position(
        width: @width,
        height: @height,
        radius:,
        existing_positions: placed_positions,
        wall_buffer: spawn_wall_buffer,
        min_distance: spawn_min_distance,
        max_distance: spawn_max_distance
      )
    rescue SpawnError
      raise SpawnError, "Could not find valid spawn position. " \
                        "Arena may be too small for #{@actors.size} rubots."
    end

    def update_bullets
      @bullets.each(&:update)

      @bullets.reject! do |bullet|
        bullet.out_of_bounds?(@width, @height) || check_bullet_hit(bullet)
      end
    end

    # Returns true if bullet hit a target and should be removed
    # Note: A bullet can only hit one target per update
    def check_bullet_hit(bullet)
      @actors.each do |actor|
        next if actor.dead?
        next unless bullet_hits_actor?(bullet, actor)

        apply_bullet_damage(bullet, actor)
        return true # Bullet consumed - exit immediately
      end

      false # No hit
    end

    def bullet_hits_actor?(bullet, actor)
      distance = Physics.distance(x1: bullet.x, y1: bullet.y, x2: actor.x, y2: actor.y)
      distance < bullet.radius + actor.radius
    end

    def apply_bullet_damage(bullet, actor)
      actor.apply_damage(bullet.damage)

      # Self-damage doesn't count toward damage_dealt (for tiebreaker fairness)
      # Dead rubots don't accumulate damage stats
      bullet.owner.add_damage_dealt(bullet.damage) if bullet.owner&.alive? && actor != bullet.owner

      direction = Math.atan2(bullet.velocity_y, bullet.velocity_x) * 180 / Math::PI
      actor.call_safely { |bot| bot.on_hit(damage: bullet.damage, direction:) }

      @event_bus.emit(EventBus::Hit.new(
                        attacker_id: bullet.owner&.id,
                        target_id: actor.id,
                        bullet_id: bullet.id,
                        x: bullet.x,
                        y: bullet.y,
                        damage: bullet.damage
                      ))
    end

    def process_fire(actor:, energy:)
      NumericValidation.validate!(energy, name: "fire energy", positive: true)

      return false unless actor.spend_energy(energy)

      damage = (energy * Config::Combat::FIRE_DAMAGE_MULTIPLIER).ceil
      radians = actor.turret_angle * Math::PI / 180
      spawn_distance = actor.radius + Config::Combat::BULLET_RADIUS
      bullet_x = actor.x + (Math.cos(radians) * spawn_distance)
      bullet_y = actor.y + (Math.sin(radians) * spawn_distance)
      bullet = Bullet.new(
        x: bullet_x,
        y: bullet_y,
        angle: actor.turret_angle,
        damage:,
        owner: actor
      )
      @bullets << bullet

      @event_bus.emit(EventBus::Fire.new(
                        actor_id: actor.id,
                        bullet_id: bullet.id,
                        x: bullet_x,
                        y: bullet_y,
                        angle: actor.turret_angle,
                        damage:
                      ))

      true
    end

    def process_shield(actor:, energy:)
      result = actor.increase_shielding(energy)
      return false unless result

      @event_bus.emit(EventBus::Shield.new(actor_id: actor.id, energy:))

      true
    end

    def process_probe(actor:, attributes:)
      cost = SensorCalculator.probe_cost(attributes)
      return false unless actor.spend_energy(cost)

      target = find_probe_target(actor)
      result = target ? build_probe_echo(target:, attributes:) : {}

      # Track that this target was probed
      target&.increment_detection(:probed)

      actor.set_sensing_results(probe: result)
      true
    end

    def find_probe_target(actor)
      radians = actor.turret_angle * Math::PI / 180
      dir_x = Math.cos(radians)
      dir_y = Math.sin(radians)

      closest_target = nil
      closest_distance = Float::INFINITY

      @actors.each do |other|
        next if other == actor || other.dead?

        hit_distance = ray_circle_intersection(
          origin_x: actor.x, origin_y: actor.y,
          dir_x:, dir_y:,
          circle_x: other.x, circle_y: other.y, radius: other.radius
        )

        next unless hit_distance
        next unless hit_distance < closest_distance

        closest_distance = hit_distance
        closest_target = other
      end

      closest_target
    end

    # Returns distance along ray to circle intersection, or nil if no hit
    def ray_circle_intersection(origin_x:, origin_y:, dir_x:, dir_y:, circle_x:, circle_y:, radius:)
      dx = circle_x - origin_x
      dy = circle_y - origin_y

      # Project circle center onto ray direction
      projection = (dx * dir_x) + (dy * dir_y)
      return nil if projection <= 0 # Circle is behind ray origin

      # Find closest point on ray to circle center
      closest_x = origin_x + (dir_x * projection)
      closest_y = origin_y + (dir_y * projection)

      # Check if ray passes through circle (use squared distance to avoid sqrt)
      dx_to_center = circle_x - closest_x
      dy_to_center = circle_y - closest_y
      dist_squared = (dx_to_center * dx_to_center) + (dy_to_center * dy_to_center)
      return nil unless dist_squared <= (radius * radius)

      projection
    end

    def build_probe_echo(target:, attributes:)
      result = {}

      if attributes.include?(:position)
        result[:x] = target.x
        result[:y] = target.y
      end

      result[:size] = target.size if attributes.include?(:size)

      if attributes.include?(:velocity)
        result[:velocity_x] = target.velocity_x
        result[:velocity_y] = target.velocity_y
      end

      result[:turret_angle] = target.turret_angle if attributes.include?(:turret_angle)
      result[:shield_level] = target.shield_level if attributes.include?(:shield)
      result[:health] = target.health if attributes.include?(:health)
      result[:energy] = target.energy if attributes.include?(:energy)

      result
    end

    def process_scan(actor:, angle:, distance:, velocity:, owner:)
      NumericValidation.validate!(angle, name: "scan angle", positive: true, max: 360)
      NumericValidation.validate!(distance, name: "scan distance", positive: true)

      cost = SensorCalculator.scan_cost(angle:, distance:, velocity:, owner:)
      return false unless actor.spend_energy(cost)

      results = []

      # Find rubots in arc
      @actors.each do |other|
        next if other == actor || other.dead?
        next unless in_arc?(actor:, angle:, distance:, x: other.x, y: other.y)

        # Track that this rubot was scanned
        other.increment_detection(:scanned)

        result = { x: other.x, y: other.y, type: :rubot }
        if velocity
          result[:velocity_x] = other.velocity_x
          result[:velocity_y] = other.velocity_y
        end
        # NOTE: rubots don't have an :owner field (only bullets do)
        results << result
      end

      # Find bullets in arc
      @bullets.each do |bullet|
        next unless in_arc?(actor:, angle:, distance:, x: bullet.x, y: bullet.y)

        result = { x: bullet.x, y: bullet.y, type: :bullet }
        if velocity
          result[:velocity_x] = bullet.velocity_x
          result[:velocity_y] = bullet.velocity_y
        end
        result[:owner] = bullet.owner&.rubot_class&.name if owner
        results << result
      end

      actor.set_sensing_results(scan: results)
      true
    end

    # Check if a point is within the scan arc
    # Arc is centered on turret_angle with arc_angle width
    def in_arc?(actor:, angle:, distance:, x:, y:)
      dx = x - actor.x
      dy = y - actor.y
      actual_distance = Math.sqrt((dx * dx) + (dy * dy))

      return false if actual_distance > distance
      return false if actual_distance < Config::Sensing::MIN_MEASURABLE_DISTANCE # Too close to measure angle

      # Calculate angle to target (in degrees)
      target_angle = Math.atan2(dy, dx) * 180 / Math::PI

      # Normalize angle difference to -180..180
      angle_diff = Physics.normalize_angle(target_angle - actor.turret_angle)

      # Check if within half the arc on either side
      angle_diff.abs <= angle / 2.0
    end

    def process_pulse(actor:, distance:, owner:)
      NumericValidation.validate!(distance, name: "pulse distance", positive: true)

      cost = SensorCalculator.pulse_cost(distance:, owner:)
      return false unless actor.spend_energy(cost)

      results = []

      # Find rubots within distance
      @actors.each do |other|
        next if other == actor || other.dead?
        next unless within_distance?(actor:, distance:, x: other.x, y: other.y)

        # Track that this rubot was pulsed
        other.increment_detection(:pulsed)

        result = { x: other.x, y: other.y, type: :rubot }
        # NOTE: rubots don't have an :owner field (only bullets do)
        results << result
      end

      # Find bullets within distance
      @bullets.each do |bullet|
        next unless within_distance?(actor:, distance:, x: bullet.x, y: bullet.y)

        result = { x: bullet.x, y: bullet.y, type: :bullet }
        result[:owner] = bullet.owner&.rubot_class&.name if owner
        results << result
      end

      actor.set_sensing_results(pulse: results)
      true
    end

    def within_distance?(actor:, distance:, x:, y:)
      Physics.distance(x1: actor.x, y1: actor.y, x2: x, y2: y) <= distance
    end

    # Spawns an energon at the position maximizing minimum distance from all bots
    def spawn_energon(chronons)
      position = find_energon_spawn_position
      unless position
        warn "[Arena] Failed to find energon spawn position at chronon #{chronons}"
        return nil
      end

      energon = Energon.spawn(x: position[:x], y: position[:y], spawn_chronon: chronons)
      @energons << energon
      energon
    end

    # Check for energon collection and return array of collection events
    def check_energon_collection(chronons)
      collections = []

      @energons.reject! do |energon|
        collector = find_energon_collector(energon)
        if collector
          amount = energon.value_int(chronons)
          collector.add_energy(amount)
          collector.call_safely { |bot| bot.on_energon(amount) }
          collections << { actor: collector, energon:, amount: }
          true # Remove this energon
        else
          false # Keep this energon
        end
      end

      collections
    end

    private

    def find_energon_spawn_position
      rubot_positions = @actors
                        .select(&:alive?)
                        .map { |r| { x: r.x, y: r.y } }

      wall_buffer = ([@width, @height].min * Config::Arena::ENERGON_WALL_BUFFER_RATIO).round

      SpawnPositionCalculator.find_energon_position(
        width: @width,
        height: @height,
        rubot_positions:,
        wall_buffer:
      )
    end

    def find_energon_collector(energon)
      @actors.find do |actor|
        next false if actor.dead?

        distance = Physics.distance(x1: energon.x, y1: energon.y, x2: actor.x, y2: actor.y)
        distance < actor.radius + Config::Energon::RADIUS
      end
    end
  end
end
