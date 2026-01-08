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
# sensing = [
#   "Probe - Check turret line for target, returns attributes",
#   "Scan - Arc scan from turret, returns positions in cone",
#   "Pulse - Omnidirectional radar ping, returns nearby objects",
#   "Detect - Counter-intelligence, reports who scanned you"
# ]

module Rubowar
  class Arena
    attr_reader :width, :height, :friction
    attr_accessor :bullets, :runners, :energons

    def initialize(width: Config::Arena::DEFAULT_WIDTH, height: Config::Arena::DEFAULT_HEIGHT,
                   friction: Config::Arena::DEFAULT_FRICTION)
      @width = width
      @height = height
      @friction = friction
      @bullets = []
      @runners = []
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

    def spawn_rubots(rubot_classes)
      @runners = rubot_classes.map { |klass| RubotActor.new(klass) }

      @runners.each do |runner|
        position = find_spawn_position(runner.radius)
        runner.set_position(position[:x], position[:y])
        runner.turret_angle = rand(360)
      end
    end

    def to_state(chronons)
      ArenaState.new(
        arena_width: @width,
        arena_height: @height,
        friction: @friction,
        chronons:,
        energons: @energons.map { |e| { x: e.x, y: e.y } },
        live_rubot_count: @runners.count(&:alive?),
        energon_spawn_interval: Config::Arena::ENERGON_SPAWN_INTERVAL,
        energon_growth_rate: Config::Energon::GROWTH_RATE
      )
    end

    # Legacy method for backwards compatibility - calls both phases
    def update
      update_rubot_physics
      update_bullet_physics
    end

    # Phase 2 physics: Move rubots, apply friction, handle collisions
    def update_rubot_physics
      @runners.each do |runner|
        next if runner.dead?

        runner.apply_friction(@friction)
        runner.move
        check_wall_collision(runner)
      end

      check_rubot_collisions
    end

    # Phase 3 physics: Move bullets, check hits
    def update_bullet_physics
      update_bullets
    end

    # Returns true if action succeeded, false if it failed (e.g., insufficient energy)
    def process_action(runner:, action:)
      case action[:type]
      when :thrust
        runner.thrust(speed: action[:speed], angle: action[:angle])
      when :turret
        runner.turn_turret(action[:degrees])
      when :fire
        process_fire(runner:, energy: action[:energy])
      when :shield
        runner.increase_shielding(action[:energy])
      when :probe
        process_probe(runner:, attributes: action[:attributes])
      when :scan
        process_scan(runner:, angle: action[:angle], distance: action[:distance], velocity: action[:velocity],
                     owner: action[:owner])
      when :pulse
        process_pulse(runner:, distance: action[:distance], owner: action[:owner])
      when :detect
        runner.process_detect
      else
        false
      end
    end

    def regenerate_and_degrade
      @runners.each do |runner|
        next if runner.dead?

        runner.regenerate_energy
        runner.degrade_shield
      end
    end

    def find_spawn_position(radius)
      max_attempts = 100
      wall_buffer = spawn_wall_buffer
      min_dist = spawn_min_distance
      max_dist = spawn_max_distance

      # Find already-placed runners (those with non-zero positions)
      placed_runners = @runners.select { |r| r.x != 0 || r.y != 0 }

      max_attempts.times do
        x = rand((wall_buffer + radius)..(@width - wall_buffer - radius))
        y = rand((wall_buffer + radius)..(@height - wall_buffer - radius))

        # Check minimum distance from all placed runners
        too_close = placed_runners.any? do |other|
          distance = Math.sqrt(((x - other.x)**2) + ((y - other.y)**2))
          distance < min_dist
        end
        next if too_close

        # Check maximum distance (at least one runner must be within max_dist, if any exist)
        if placed_runners.any?
          close_enough = placed_runners.any? do |other|
            distance = Math.sqrt(((x - other.x)**2) + ((y - other.y)**2))
            distance <= max_dist
          end
          next unless close_enough
        end

        return { x:, y: }
      end

      raise SpawnError, "Could not find valid spawn position after #{max_attempts} attempts. " \
                        "Arena may be too small for #{@runners.size} rubots."
    end

    def check_wall_collision(runner)
      hit_x = false
      hit_y = false
      total_damage = 0

      # Check X walls
      if (runner.x - runner.radius).negative?
        runner.x = runner.radius
        hit_x = true
        total_damage += handle_wall_bounce_x(runner, 0)
      elsif runner.x + runner.radius > @width
        runner.x = @width - runner.radius
        hit_x = true
        total_damage += handle_wall_bounce_x(runner, @width)
      end

      # Check Y walls
      if (runner.y - runner.radius).negative?
        runner.y = runner.radius
        hit_y = true
        total_damage += handle_wall_bounce_y(runner, 0)
      elsif runner.y + runner.radius > @height
        runner.y = @height - runner.radius
        hit_y = true
        total_damage += handle_wall_bounce_y(runner, @height)
      end

      return unless hit_x || hit_y

      runner.apply_collision_damage(total_damage)
      runner.safe_callback(:on_wall)
    end

    def handle_wall_bounce_x(runner, wall_x)
      normal_x = wall_x.zero? ? 1.0 : -1.0
      mass = Physics.mass_factor(runner.radius)

      damage = Physics.wall_damage(
        vx: runner.velocity_x, vy: runner.velocity_y,
        normal_x: normal_x, normal_y: 0.0, mass: mass
      )

      if (result = Physics.wall_bounce(
        vx: runner.velocity_x, vy: runner.velocity_y,
        normal_x: normal_x, normal_y: 0.0, bot_mass: mass
      ))
        runner.set_velocity(result[:vx], result[:vy])
      end

      damage
    end

    def handle_wall_bounce_y(runner, wall_y)
      normal_y = wall_y.zero? ? 1.0 : -1.0
      mass = Physics.mass_factor(runner.radius)

      damage = Physics.wall_damage(
        vx: runner.velocity_x, vy: runner.velocity_y,
        normal_x: 0.0, normal_y: normal_y, mass: mass
      )

      if (result = Physics.wall_bounce(
        vx: runner.velocity_x, vy: runner.velocity_y,
        normal_x: 0.0, normal_y: normal_y, bot_mass: mass
      ))
        runner.set_velocity(result[:vx], result[:vy])
      end

      damage
    end

    def check_rubot_collisions
      # Phase 1: Detect all collisions and calculate responses
      # This prevents race conditions where position changes during iteration
      # affect subsequent collision calculations
      collision_responses = []

      @runners.combination(2).each do |runner_a, runner_b|
        next if runner_a.dead? || runner_b.dead?

        distance = Math.sqrt(((runner_a.x - runner_b.x)**2) + ((runner_a.y - runner_b.y)**2))
        min_distance = runner_a.radius + runner_b.radius

        next unless distance < min_distance

        # Calculate position adjustments and velocity changes without applying them
        response = calculate_collision_response(runner_a, runner_b, distance, min_distance)
        collision_responses << response
      end

      # Phase 2: Apply all position adjustments atomically
      collision_responses.each do |response|
        response[:runner_a].adjust_position(response[:pos_adjust_a_x], response[:pos_adjust_a_y])
        response[:runner_b].adjust_position(response[:pos_adjust_b_x], response[:pos_adjust_b_y])
      end

      # Phase 3: Apply all velocity changes atomically
      collision_responses.each do |response|
        response[:runner_a].adjust_velocity(response[:vel_adjust_a_x], response[:vel_adjust_a_y])
        response[:runner_b].adjust_velocity(response[:vel_adjust_b_x], response[:vel_adjust_b_y])
      end

      # Phase 4: Apply damage and callbacks (after all physics resolved)
      collision_responses.each do |response|
        response[:runner_a].apply_collision_damage(response[:damage_to_a])
        response[:runner_b].apply_collision_damage(response[:damage_to_b])

        response[:runner_a].safe_callback(:on_collision, response[:runner_b].to_state)
        response[:runner_b].safe_callback(:on_collision, response[:runner_a].to_state)
      end
    end

    def calculate_collision_response(runner_a, runner_b, distance, min_distance)
      overlap = min_distance - distance
      mass_a = Physics.mass_factor(runner_a.radius)
      mass_b = Physics.mass_factor(runner_b.radius)

      # Collision normal (from A to B)
      nx = (runner_b.x - runner_a.x) / distance
      ny = (runner_b.y - runner_a.y) / distance

      separation = Physics.collision_separation(
        a_x: runner_a.x, a_y: runner_a.y,
        b_x: runner_b.x, b_y: runner_b.y,
        distance: distance, overlap: overlap
      )

      bounce = Physics.collision_bounce(
        a_vx: runner_a.velocity_x, a_vy: runner_a.velocity_y,
        b_vx: runner_b.velocity_x, b_vy: runner_b.velocity_y,
        nx: nx, ny: ny, mass_a: mass_a, mass_b: mass_b
      )

      {
        runner_a: runner_a,
        runner_b: runner_b,
        pos_adjust_a_x: separation[:a_x],
        pos_adjust_a_y: separation[:a_y],
        pos_adjust_b_x: separation[:b_x],
        pos_adjust_b_y: separation[:b_y],
        vel_adjust_a_x: bounce[:a_vx],
        vel_adjust_a_y: bounce[:a_vy],
        vel_adjust_b_x: bounce[:b_vx],
        vel_adjust_b_y: bounce[:b_vy],
        damage_to_a: Physics.collision_damage(
          rel_vx: runner_b.velocity_x - runner_a.velocity_x,
          rel_vy: runner_b.velocity_y - runner_a.velocity_y,
          mass: mass_b
        ),
        damage_to_b: Physics.collision_damage(
          rel_vx: runner_a.velocity_x - runner_b.velocity_x,
          rel_vy: runner_a.velocity_y - runner_b.velocity_y,
          mass: mass_a
        )
      }
    end

    def update_bullets
      @bullets.each(&:update)

      @bullets.reject! do |bullet|
        bullet.out_of_bounds?(@width, @height) || check_bullet_hit(bullet)
      end
    end

    def check_bullet_hit(bullet)
      @runners.each do |runner|
        next if runner.dead?

        distance = Math.sqrt(((bullet.x - runner.x)**2) + ((bullet.y - runner.y)**2))
        next unless distance < bullet.radius + runner.radius

        runner.apply_damage(bullet.damage)
        # Self-damage doesn't count toward damage_dealt (for tiebreaker fairness)
        bullet.owner.damage_dealt += bullet.damage unless runner == bullet.owner

        direction = Math.atan2(bullet.velocity_y, bullet.velocity_x) * 180 / Math::PI
        runner.safe_callback(:on_hit, bullet.damage, direction)

        return true
      end

      false
    end

    def process_fire(runner:, energy:)
      return false unless runner.spend_energy(energy)

      damage = (energy * Config::Combat::FIRE_DAMAGE_MULTIPLIER).ceil
      radians = runner.turret_angle * Math::PI / 180
      spawn_distance = runner.radius + Config::Combat::BULLET_RADIUS
      bullet = Bullet.new(
        x: runner.x + (Math.cos(radians) * spawn_distance),
        y: runner.y + (Math.sin(radians) * spawn_distance),
        angle: runner.turret_angle,
        damage:,
        owner: runner
      )
      @bullets << bullet
      true
    end

    def process_probe(runner:, attributes:)
      cost = SensorCalculations.probe_cost(attributes)
      return false unless runner.spend_energy(cost)

      target = find_probe_target(runner)
      result = target ? build_probe_result(target:, attributes:) : {}

      # Track that this target was probed
      target.times_probed += 1 if target

      runner.instance.probe_result = result
      true
    end

    def find_probe_target(runner)
      radians = runner.turret_angle * Math::PI / 180
      dir_x = Math.cos(radians)
      dir_y = Math.sin(radians)

      closest_target = nil
      closest_distance = Float::INFINITY

      @runners.each do |other|
        next if other == runner || other.dead?

        # Vector from runner to other
        dx = other.x - runner.x
        dy = other.y - runner.y

        # Project onto ray direction
        projection = (dx * dir_x) + (dy * dir_y)
        next if projection <= 0 # Behind the runner

        # Closest point on ray to other's center
        closest_x = runner.x + (dir_x * projection)
        closest_y = runner.y + (dir_y * projection)

        # Distance from closest point to other's center
        dist_to_center = Math.sqrt(((closest_x - other.x)**2) + ((closest_y - other.y)**2))

        # Check if ray passes through other's radius
        next unless dist_to_center <= other.radius

        # Use projection as distance (how far along the ray)
        if projection < closest_distance
          closest_distance = projection
          closest_target = other
        end
      end

      closest_target
    end

    def build_probe_result(target:, attributes:)
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

    def process_scan(runner:, angle:, distance:, velocity:, owner:)
      cost = SensorCalculations.scan_cost(angle:, distance:, velocity:, owner:)
      return false unless runner.spend_energy(cost)

      results = []

      # Find rubots in arc
      @runners.each do |other|
        next if other == runner || other.dead?
        next unless in_arc?(runner:, angle:, distance:, x: other.x, y: other.y)

        # Track that this rubot was scanned
        other.times_scanned += 1

        result = { x: other.x, y: other.y, type: :rubot }
        if velocity
          result[:velocity_x] = other.velocity_x
          result[:velocity_y] = other.velocity_y
        end
        result[:owner] = nil if owner
        results << result
      end

      # Find bullets in arc
      @bullets.each do |bullet|
        next unless in_arc?(runner:, angle:, distance:, x: bullet.x, y: bullet.y)

        result = { x: bullet.x, y: bullet.y, type: :bullet }
        if velocity
          result[:velocity_x] = bullet.velocity_x
          result[:velocity_y] = bullet.velocity_y
        end
        result[:owner] = bullet.owner.rubot_class.name if owner
        results << result
      end

      runner.instance.scan_result = results
      true
    end

    # Check if a point is within the scan arc
    # Arc is centered on turret_angle with arc_angle width
    def in_arc?(runner:, angle:, distance:, x:, y:)
      dx = x - runner.x
      dy = y - runner.y
      actual_distance = Math.sqrt((dx * dx) + (dy * dy))

      return false if actual_distance > distance
      return false if actual_distance < Float::EPSILON # Too close to measure angle

      # Calculate angle to target (in degrees)
      target_angle = Math.atan2(dy, dx) * 180 / Math::PI

      # Normalize angle difference to -180..180
      angle_diff = (target_angle - runner.turret_angle) % 360
      angle_diff -= 360 if angle_diff > 180

      # Check if within half the arc on either side
      angle_diff.abs <= angle / 2.0
    end

    def process_pulse(runner:, distance:, owner:)
      cost = SensorCalculations.pulse_cost(distance:, owner:)
      return false unless runner.spend_energy(cost)

      results = []

      # Find rubots within distance
      @runners.each do |other|
        next if other == runner || other.dead?
        next unless within_distance?(runner:, distance:, x: other.x, y: other.y)

        # Track that this rubot was pulsed
        other.times_pulsed += 1

        result = { x: other.x, y: other.y, type: :rubot }
        result[:owner] = nil if owner
        results << result
      end

      # Find bullets within distance
      @bullets.each do |bullet|
        next unless within_distance?(runner:, distance:, x: bullet.x, y: bullet.y)

        result = { x: bullet.x, y: bullet.y, type: :bullet }
        result[:owner] = bullet.owner.rubot_class.name if owner
        results << result
      end

      runner.instance.pulse_result = results
      true
    end

    def within_distance?(runner:, distance:, x:, y:)
      Physics.distance(runner.x, runner.y, x, y) <= distance
    end

    # Spawns an energon at the position maximizing minimum distance from all bots
    def spawn_energon(chronons)
      position = find_energon_spawn_position
      return nil unless position

      energon = Energon.new(x: position[:x], y: position[:y], spawn_chronon: chronons)
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
          collector.energy = [collector.energy + amount, collector.max_energy].min
          collector.safe_callback(:on_energon, amount)
          collections << { runner: collector, energon:, amount: }
          true # Remove this energon
        else
          false # Keep this energon
        end
      end

      collections
    end

    private

    def find_energon_spawn_position
      alive_runners = @runners.select(&:alive?)
      return { x: @width / 2.0, y: @height / 2.0 } if alive_runners.empty?

      candidates = []
      best_min_distance = -1

      # Calculate wall buffer based on arena size (15% of smaller dimension)
      wall_buffer = ([@width, @height].min * Config::Arena::ENERGON_WALL_BUFFER_RATIO).round

      # Sample candidate positions using a grid
      grid_step = 20
      (wall_buffer..(@width - wall_buffer)).step(grid_step) do |cx|
        (wall_buffer..(@height - wall_buffer)).step(grid_step) do |cy|
          # Find minimum distance to any alive bot
          min_dist = alive_runners.map do |runner|
            Math.sqrt(((cx - runner.x)**2) + ((cy - runner.y)**2))
          end.min

          # Tolerance of 20 units for "equally good" positions
          if min_dist > best_min_distance + 20
            best_min_distance = min_dist
            candidates = [{ x: cx.to_f, y: cy.to_f }]
          elsif min_dist >= best_min_distance - 20
            candidates << { x: cx.to_f, y: cy.to_f }
          end
        end
      end

      # Pick randomly from equally-good candidates
      candidates.sample
    end

    def find_energon_collector(energon)
      @runners.find do |runner|
        next false if runner.dead?

        distance = Math.sqrt(((energon.x - runner.x)**2) + ((energon.y - runner.y)**2))
        distance < runner.radius + Config::Energon::RADIUS
      end
    end
  end
end
