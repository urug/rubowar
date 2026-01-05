# frozen_string_literal: true

module Rubowar
  class Arena
    DEFAULT_WIDTH = 800
    DEFAULT_HEIGHT = 600
    DEFAULT_FRICTION = 0.95
    WALL_DAMAGE = 10
    COLLISION_DAMAGE = 5
    SIZE_COLLISION_BONUS = 3
    MIN_SPAWN_WALL_DISTANCE = 50
    MIN_SPAWN_RUBOT_DISTANCE = 100
    THRUST_MULTIPLIER = 1.5
    FIRE_DAMAGE_MULTIPLIER = 1.5
    BODY_TURN_DIVISOR = 10.0
    TURRET_TURN_DIVISOR = 30.0

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
        runner.body_angle = rand(360)
        runner.turret_angle = runner.body_angle
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
        process_thrust(runner, action[:energy])
      when :turn
        process_turn(runner, action[:degrees])
      when :turret
        process_turret(runner, action[:degrees])
      when :fire
        process_fire(runner, action[:energy])
      when :shield
        process_shield(runner, action[:energy])
      when :look
        process_look(runner, action[:energy])
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
        runner.apply_damage(WALL_DAMAGE)
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

        # Apply damage with size modifiers
        damage_to_a = calculate_collision_damage(runner_b.size, runner_a.size)
        damage_to_b = calculate_collision_damage(runner_a.size, runner_b.size)

        runner_a.apply_damage(damage_to_a)
        runner_b.apply_damage(damage_to_b)

        runner_a.instance.on_collision(runner_b.to_state)
        runner_b.instance.on_collision(runner_a.to_state)
      end
    end

    def calculate_collision_damage(attacker_size, defender_size)
      damage = COLLISION_DAMAGE

      size_order = { small: 0, medium: 1, large: 2 }
      attacker_rank = size_order[attacker_size]
      defender_rank = size_order[defender_size]

      if attacker_rank > defender_rank
        damage += SIZE_COLLISION_BONUS
      elsif attacker_rank < defender_rank
        damage -= SIZE_COLLISION_BONUS
      end

      [damage, 0].max
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

    def process_thrust(runner, energy)
      return false unless runner.spend_energy(energy)

      velocity_gain = Math.sqrt(energy) * THRUST_MULTIPLIER
      radians = runner.body_angle * Math::PI / 180
      runner.velocity_x += Math.cos(radians) * velocity_gain
      runner.velocity_y += Math.sin(radians) * velocity_gain
      true
    end

    def process_turn(runner, degrees)
      cost = degrees.abs / BODY_TURN_DIVISOR
      return false unless runner.spend_energy(cost)

      runner.body_angle = (runner.body_angle + degrees) % 360
      true
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
      bullet = Bullet.new(
        x: runner.x,
        y: runner.y,
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

    def process_look(runner, energy)
      return false unless runner.spend_energy(energy)

      target = find_rubot_in_line_of_sight(runner)
      result = build_look_result(target, energy) if target

      runner.instance.instance_variable_set(:@_look_result, result)
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

    def build_look_result(target, energy_level)
      result = {
        x: target.x,
        y: target.y,
        size: target.size
      }

      if energy_level >= 2
        result[:velocity_x] = target.velocity_x
        result[:velocity_y] = target.velocity_y
      end

      result[:shield_level] = target.shield_level if energy_level >= 3
      result[:health] = target.health if energy_level >= 4
      result[:energy] = target.energy if energy_level >= 5

      result
    end
  end
end
