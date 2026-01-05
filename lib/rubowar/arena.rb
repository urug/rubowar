# frozen_string_literal: true

module Rubowar
  class Arena
    DEFAULT_WIDTH = 800
    DEFAULT_HEIGHT = 600
    DEFAULT_FRICTION = 0.95
    COLLISION_BASE_DAMAGE = 2
    COLLISION_VELOCITY_MULTIPLIER = 0.5
    WALL_VELOCITY_MULTIPLIER = 0.75
    MIN_SPAWN_WALL_DISTANCE = 50
    MIN_SPAWN_RUBOT_DISTANCE = 100
    THRUST_MULTIPLIER = 1.5
    FIRE_DAMAGE_MULTIPLIER = 1.5
    TURRET_TURN_DIVISOR = 30.0
    LOOK_BASE_COST = 1
    LOOK_COSTS = {
      size: 1,
      velocity: 2,
      shield: 2,
      health: 3,
      energy: 3
    }.freeze

    attr_reader :width, :height, :friction, :bullets, :runners

    def initialize(width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT, friction: DEFAULT_FRICTION)
      @width = width
      @height = height
      @friction = friction
      @bullets = []
      @runners = []
      @energons = []
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
        energons: @energons.map { |e| { x: e[:x], y: e[:y] } }
      )
    end

    def update
      @runners.each do |runner|
        next if runner.dead?

        apply_friction(runner)
        move_rubot(runner)
        runner.clamp_speed
        check_wall_collision(runner)
      end

      check_rubot_collisions
      update_bullets
    end

    # Returns true if action succeeded, false if it failed (e.g., insufficient energy)
    def process_action(runner, action)
      case action[:type]
      when :thrust
        process_thrust(runner, action[:speed], action[:angle])
      when :turret
        process_turret(runner, action[:degrees])
      when :fire
        process_fire(runner, action[:energy])
      when :shield
        process_shield(runner, action[:energy])
      when :look
        process_look(runner, action[:attributes])
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

    private

    def find_spawn_position(radius)
      max_attempts = 100

      max_attempts.times do
        x = rand(MIN_SPAWN_WALL_DISTANCE + radius..@width - MIN_SPAWN_WALL_DISTANCE - radius)
        y = rand(MIN_SPAWN_WALL_DISTANCE + radius..@height - MIN_SPAWN_WALL_DISTANCE - radius)

        valid = @runners.all? do |other|
          distance = Math.sqrt((x - other.x)**2 + (y - other.y)**2)
          distance >= MIN_SPAWN_RUBOT_DISTANCE
        end

        return { x: x, y: y } if valid
      end

      # Fallback: just place it somewhere valid for walls
      {
        x: rand(MIN_SPAWN_WALL_DISTANCE + radius..@width - MIN_SPAWN_WALL_DISTANCE - radius),
        y: rand(MIN_SPAWN_WALL_DISTANCE + radius..@height - MIN_SPAWN_WALL_DISTANCE - radius)
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

      if runner.x - runner.radius < 0
        runner.x = runner.radius
        runner.velocity_x = -runner.velocity_x
        hit_wall = true
      elsif runner.x + runner.radius > @width
        runner.x = @width - runner.radius
        runner.velocity_x = -runner.velocity_x
        hit_wall = true
      end

      if runner.y - runner.radius < 0
        runner.y = runner.radius
        runner.velocity_y = -runner.velocity_y
        hit_wall = true
      elsif runner.y + runner.radius > @height
        runner.y = @height - runner.radius
        runner.velocity_y = -runner.velocity_y
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
        bullet.owner.damage_dealt += bullet.damage

        direction = Math.atan2(bullet.velocity_y, bullet.velocity_x) * 180 / Math::PI
        runner.instance.on_hit(bullet.damage, direction)

        return true
      end

      false
    end

    def process_thrust(runner, desired_speed, angle)
      return false if runner.energy <= 0

      mass = mass_factor(runner)
      direction_multiplier = thrust_momentum_multiplier(runner, angle)
      base_cost = (desired_speed / THRUST_MULTIPLIER)**2
      required_energy = base_cost * mass * direction_multiplier

      if runner.energy >= required_energy
        # Full thrust
        runner.energy -= required_energy
        actual_speed = desired_speed
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

    def thrust_momentum_multiplier(runner, thrust_angle)
      return 1.0 if runner.speed < 0.1 # Not moving, no penalty

      current_angle = Math.atan2(runner.velocity_y, runner.velocity_x) * 180 / Math::PI
      angle_diff = (thrust_angle - current_angle).abs % 360
      angle_diff = 360 - angle_diff if angle_diff > 180

      # 0° diff = 1.0x, 90° diff = 1.5x, 180° diff = 2.0x
      1.0 + (angle_diff / 180.0)
    end

    def process_turret(runner, degrees)
      cost = degrees.abs / TURRET_TURN_DIVISOR
      return false unless runner.spend_energy(cost)

      runner.turret_angle = (runner.turret_angle + degrees) % 360
      true
    end

    def process_fire(runner, energy)
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

    def process_shield(runner, energy)
      return false unless runner.spend_energy(energy)

      runner.shield_level = [runner.shield_level + energy, RubotRunner::MAX_SHIELD].min
      true
    end

    def process_look(runner, attributes)
      cost = LOOK_BASE_COST + attributes.sum { |attr| LOOK_COSTS[attr] }
      return false unless runner.spend_energy(cost)

      target = find_rubot_in_line_of_sight(runner)
      result = build_look_result(target, attributes) if target

      runner.instance._look_result = result
      true
    end

    def find_rubot_in_line_of_sight(runner)
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

    def build_look_result(target, attributes)
      result = {
        x: target.x,
        y: target.y
      }

      result[:size] = target.size if attributes.include?(:size)

      if attributes.include?(:velocity)
        result[:velocity_x] = target.velocity_x
        result[:velocity_y] = target.velocity_y
      end

      result[:shield_level] = target.shield_level if attributes.include?(:shield)
      result[:health] = target.health if attributes.include?(:health)
      result[:energy] = target.energy if attributes.include?(:energy)

      result
    end
  end
end
