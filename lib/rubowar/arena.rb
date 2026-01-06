# frozen_string_literal: true

module Rubowar
  class Arena
    include SensingCosts

    DEFAULT_WIDTH = 800
    DEFAULT_HEIGHT = 600
    DEFAULT_FRICTION = 0.95
    COLLISION_BASE_DAMAGE = 2
    COLLISION_VELOCITY_MULTIPLIER = 0.5
    WALL_VELOCITY_MULTIPLIER = 0.75
    WALL_BOUNCE_COEFFICIENT = 0.12
    # Spawn distance ratios (relative to arena dimensions)
    SPAWN_WALL_BUFFER_RATIO = 0.08        # 8% of smaller dimension
    SPAWN_MIN_DISTANCE_RATIO = 0.12       # 12% of diagonal
    SPAWN_MAX_DISTANCE_RATIO = 0.50       # 50% of diagonal
    THRUST_MULTIPLIER = 1.5
    FIRE_DAMAGE_MULTIPLIER = 1.5
    TURRET_TURN_DIVISOR = 24.0
    STATIONARY_SPEED_THRESHOLD = 0.1
    ENERGON_WALL_BUFFER_RATIO = 0.15  # 15% of smaller dimension
    ENERGON_SPAWN_INTERVAL = 80

    attr_reader :width, :height, :friction
    attr_accessor :bullets, :runners, :energons

    def initialize(width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT, friction: DEFAULT_FRICTION)
      @width = width
      @height = height
      @friction = friction
      @bullets = []
      @runners = []
      @energons = []
    end

    # Spawn distance calculations based on arena size
    def arena_diagonal
      Math.sqrt(@width**2 + @height**2)
    end

    def spawn_wall_buffer
      ([@width, @height].min * SPAWN_WALL_BUFFER_RATIO).round
    end

    def spawn_min_distance
      (arena_diagonal * SPAWN_MIN_DISTANCE_RATIO).round
    end

    def spawn_max_distance
      (arena_diagonal * SPAWN_MAX_DISTANCE_RATIO).round
    end

    def spawn_rubots(rubot_classes)
      @runners = rubot_classes.map { |klass| RubotRunner.new(klass) }

      @runners.each do |runner|
        position = find_spawn_position(runner.radius)
        runner.x = position[:x]
        runner.y = position[:y]
        runner.turret_angle = rand(360)
      end
    end

    def to_state(tick_number)
      ArenaState.new(
        arena_width: @width,
        arena_height: @height,
        friction: @friction,
        tick_number: tick_number,
        energons: @energons.map { |e| { x: e.x, y: e.y } },
        live_rubot_count: @runners.count { |r| r.alive? },
        energon_spawn_interval: ENERGON_SPAWN_INTERVAL,
        energon_growth_rate: Energon::GROWTH_RATE
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

        apply_friction(runner)
        move_rubot(runner)
        runner.clamp_speed
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
        process_thrust(runner: runner, speed: action[:speed], angle: action[:angle])
      when :turret
        process_turret(runner: runner, degrees: action[:degrees])
      when :fire
        process_fire(runner: runner, energy: action[:energy])
      when :shield
        process_shield(runner: runner, energy: action[:energy])
      when :probe
        process_probe(runner: runner, attributes: action[:attributes])
      when :scan
        process_scan(runner: runner, angle: action[:angle], distance: action[:distance], velocity: action[:velocity], owner: action[:owner])
      when :pulse
        process_pulse(runner: runner, distance: action[:distance], owner: action[:owner])
      when :detect
        process_detect(runner: runner)
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
        x = rand(wall_buffer + radius..@width - wall_buffer - radius)
        y = rand(wall_buffer + radius..@height - wall_buffer - radius)

        # Check minimum distance from all placed runners
        too_close = placed_runners.any? do |other|
          distance = Math.sqrt((x - other.x)**2 + (y - other.y)**2)
          distance < min_dist
        end
        next if too_close

        # Check maximum distance (at least one runner must be within max_dist, if any exist)
        if placed_runners.any?
          close_enough = placed_runners.any? do |other|
            distance = Math.sqrt((x - other.x)**2 + (y - other.y)**2)
            distance <= max_dist
          end
          next unless close_enough
        end

        return { x: x, y: y }
      end

      # Fallback: just place it somewhere valid for walls
      {
        x: rand(wall_buffer + radius..@width - wall_buffer - radius),
        y: rand(wall_buffer + radius..@height - wall_buffer - radius)
      }
    end

    def apply_friction(runner)
      runner.velocity_x *= @friction
      runner.velocity_y *= @friction
    end

    def move_rubot(runner)
      runner.x += runner.velocity_x
      runner.y += runner.velocity_y
    end

    def check_wall_collision(runner)
      hit_wall = false
      bounce_factor = mass_factor(runner) * WALL_BOUNCE_COEFFICIENT

      if runner.x - runner.radius < 0
        runner.x = runner.radius
        runner.velocity_x = -runner.velocity_x * bounce_factor
        hit_wall = true
      elsif runner.x + runner.radius > @width
        runner.x = @width - runner.radius
        runner.velocity_x = -runner.velocity_x * bounce_factor
        hit_wall = true
      end

      if runner.y - runner.radius < 0
        runner.y = runner.radius
        runner.velocity_y = -runner.velocity_y * bounce_factor
        hit_wall = true
      elsif runner.y + runner.radius > @height
        runner.y = @height - runner.radius
        runner.velocity_y = -runner.velocity_y * bounce_factor
        hit_wall = true
      end

      if hit_wall
        runner.apply_damage(calculate_wall_damage(runner))
        runner.instance.on_wall
      end
    end

    def check_rubot_collisions
      @runners.combination(2).each do |runner_a, runner_b|
        next if runner_a.dead? || runner_b.dead?

        distance = Math.sqrt((runner_a.x - runner_b.x)**2 + (runner_a.y - runner_b.y)**2)
        min_distance = runner_a.radius + runner_b.radius

        next unless distance < min_distance

        # Push apart
        overlap = min_distance - distance
        if distance > 0
          dx = (runner_a.x - runner_b.x) / distance
          dy = (runner_a.y - runner_b.y) / distance
          runner_a.x += dx * overlap / 2
          runner_a.y += dy * overlap / 2
          runner_b.x -= dx * overlap / 2
          runner_b.y -= dy * overlap / 2
        end

        # Apply momentum-based damage
        damage_to_a = calculate_collision_damage(runner_b)
        damage_to_b = calculate_collision_damage(runner_a)

        runner_a.apply_damage(damage_to_a)
        runner_b.apply_damage(damage_to_b)

        runner_a.instance.on_collision(runner_b.to_state)
        runner_b.instance.on_collision(runner_a.to_state)
      end
    end

    def calculate_wall_damage(runner)
      (COLLISION_BASE_DAMAGE + runner.speed * WALL_VELOCITY_MULTIPLIER).round
    end

    def calculate_collision_damage(attacker)
      mass = mass_factor(attacker)
      momentum_damage = mass * attacker.speed * COLLISION_VELOCITY_MULTIPLIER
      (COLLISION_BASE_DAMAGE + momentum_damage).round
    end

    def mass_factor(runner)
      medium_radius = RubotRunner::SIZES[:medium][:radius].to_f
      (runner.radius / medium_radius)**2
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

        distance = Math.sqrt((bullet.x - runner.x)**2 + (bullet.y - runner.y)**2)
        next unless distance < bullet.radius + runner.radius

        runner.apply_damage(bullet.damage)
        # Self-damage doesn't count toward damage_dealt (for tiebreaker fairness)
        bullet.owner.damage_dealt += bullet.damage unless runner == bullet.owner

        direction = Math.atan2(bullet.velocity_y, bullet.velocity_x) * 180 / Math::PI
        runner.instance.on_hit(bullet.damage, direction)

        return true
      end

      false
    end

    def process_thrust(runner:, speed:, angle:)
      return false if runner.energy <= 0

      mass = mass_factor(runner)
      direction_multiplier = thrust_momentum_multiplier(runner: runner, angle: angle)
      base_cost = (speed / THRUST_MULTIPLIER)**2
      required_energy = base_cost * mass * direction_multiplier

      if runner.energy >= required_energy
        # Full thrust
        runner.energy -= required_energy
        actual_speed = speed
      else
        # Partial thrust - use all remaining energy
        available_energy = runner.energy
        runner.energy = 0
        # Reverse the formula: speed = sqrt(energy / (mass * direction_multiplier)) * THRUST_MULTIPLIER
        effective_energy = available_energy / (mass * direction_multiplier)
        actual_speed = Math.sqrt(effective_energy) * THRUST_MULTIPLIER
      end

      radians = angle * Math::PI / 180
      runner.velocity_x += Math.cos(radians) * actual_speed
      runner.velocity_y += Math.sin(radians) * actual_speed
      true
    end

    def thrust_momentum_multiplier(runner:, angle:)
      return 1.0 if runner.speed < STATIONARY_SPEED_THRESHOLD

      current_angle = Math.atan2(runner.velocity_y, runner.velocity_x) * 180 / Math::PI
      angle_diff = (angle - current_angle).abs % 360
      angle_diff = 360 - angle_diff if angle_diff > 180

      # 0° diff = 1.0x, 90° diff = 1.5x, 180° diff = 2.0x
      1.0 + (angle_diff / 180.0)
    end

    def process_turret(runner:, degrees:)
      cost = degrees.abs / TURRET_TURN_DIVISOR
      return false unless runner.spend_energy(cost)

      runner.turret_angle = (runner.turret_angle + degrees) % 360
      true
    end

    def process_fire(runner:, energy:)
      return false unless runner.spend_energy(energy)

      damage = energy * FIRE_DAMAGE_MULTIPLIER
      radians = runner.turret_angle * Math::PI / 180
      spawn_distance = runner.radius + Bullet::RADIUS
      bullet = Bullet.new(
        x: runner.x + Math.cos(radians) * spawn_distance,
        y: runner.y + Math.sin(radians) * spawn_distance,
        angle: runner.turret_angle,
        damage: damage,
        owner: runner
      )
      @bullets << bullet
      true
    end

    def process_shield(runner:, energy:)
      return false unless runner.spend_energy(energy)

      runner.shield_level = [runner.shield_level + energy, runner.max_shield].min
      true
    end

    def process_probe(runner:, attributes:)
      cost = probe_cost(attributes)
      return false unless runner.spend_energy(cost)

      target = find_probe_target(runner)
      result = target ? build_probe_result(target: target, attributes: attributes) : {}

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
        projection = dx * dir_x + dy * dir_y
        next if projection <= 0 # Behind the runner

        # Closest point on ray to other's center
        closest_x = runner.x + dir_x * projection
        closest_y = runner.y + dir_y * projection

        # Distance from closest point to other's center
        dist_to_center = Math.sqrt((closest_x - other.x)**2 + (closest_y - other.y)**2)

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
      cost = scan_cost(angle: angle, distance: distance, velocity: velocity, owner: owner)
      return false unless runner.spend_energy(cost)

      results = []

      # Find rubots in arc
      @runners.each do |other|
        next if other == runner || other.dead?
        next unless in_arc?(runner: runner, angle: angle, distance: distance, x: other.x, y: other.y)

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
        next unless in_arc?(runner: runner, angle: angle, distance: distance, x: bullet.x, y: bullet.y)

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
      actual_distance = Math.sqrt(dx * dx + dy * dy)

      return false if actual_distance > distance
      return false if actual_distance < 0.001 # Too close to measure angle

      # Calculate angle to target (in degrees)
      target_angle = Math.atan2(dy, dx) * 180 / Math::PI

      # Normalize angle difference to -180..180
      angle_diff = (target_angle - runner.turret_angle) % 360
      angle_diff -= 360 if angle_diff > 180

      # Check if within half the arc on either side
      angle_diff.abs <= angle / 2.0
    end

    def process_pulse(runner:, distance:, owner:)
      cost = pulse_cost(distance: distance, owner: owner)
      return false unless runner.spend_energy(cost)

      results = []

      # Find rubots within distance
      @runners.each do |other|
        next if other == runner || other.dead?
        next unless within_distance?(runner: runner, distance: distance, x: other.x, y: other.y)

        # Track that this rubot was pulsed
        other.times_pulsed += 1

        result = { x: other.x, y: other.y, type: :rubot }
        result[:owner] = nil if owner
        results << result
      end

      # Find bullets within distance
      @bullets.each do |bullet|
        next unless within_distance?(runner: runner, distance: distance, x: bullet.x, y: bullet.y)

        result = { x: bullet.x, y: bullet.y, type: :bullet }
        result[:owner] = bullet.owner.rubot_class.name if owner
        results << result
      end

      runner.instance.pulse_result = results
      true
    end

    def within_distance?(runner:, distance:, x:, y:)
      dx = x - runner.x
      dy = y - runner.y
      actual_distance = Math.sqrt(dx * dx + dy * dy)
      actual_distance <= distance
    end

    def process_detect(runner:)
      cost = detect_cost
      return false unless runner.spend_energy(cost)

      # Return the detection counts from this tick
      result = {
        probed: runner.times_probed,
        scanned: runner.times_scanned,
        pulsed: runner.times_pulsed
      }

      runner.instance.detect_result = result
      true
    end

    # Spawns an energon at the position maximizing minimum distance from all bots
    def spawn_energon(tick_number)
      position = find_energon_spawn_position
      return nil unless position

      energon = Energon.new(x: position[:x], y: position[:y], spawn_tick: tick_number)
      @energons << energon
      energon
    end

    # Check for energon collection and return array of collection events
    def check_energon_collection(tick_number)
      collections = []

      @energons.reject! do |energon|
        collector = find_energon_collector(energon)
        if collector
          amount = energon.value_int(tick_number)
          collector.energy = [collector.energy + amount, RubotRunner::MAX_ENERGY].min
          collector.instance.on_energon(amount)
          collections << { runner: collector, energon: energon, amount: amount }
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
      wall_buffer = ([@width, @height].min * ENERGON_WALL_BUFFER_RATIO).round

      # Sample candidate positions using a grid
      grid_step = 20
      (wall_buffer..(@width - wall_buffer)).step(grid_step) do |cx|
        (wall_buffer..(@height - wall_buffer)).step(grid_step) do |cy|
          # Find minimum distance to any alive bot
          min_dist = alive_runners.map do |runner|
            Math.sqrt((cx - runner.x)**2 + (cy - runner.y)**2)
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

        distance = Math.sqrt((energon.x - runner.x)**2 + (energon.y - runner.y)**2)
        distance < runner.radius + Energon::RADIUS
      end
    end
  end
end
